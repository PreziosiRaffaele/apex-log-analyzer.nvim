local Job = require("plenary.job")

local M = {}

-- Local function to apply syntax highlighting directly to the current buffer.
local function apply_syntax()
	-- Define syntax matches for each event type using "very magic" regex.
	vim.cmd("syntax match ApexLogMethod    /\\vMETHOD/")
	vim.cmd("syntax match ApexLogSOQL      /\\vSOQL/")
	vim.cmd("syntax match ApexLogDML       /\\vDML/")
    vim.cmd("syntax match FlowLog         /\\v(FLOW|FLOW_START_INTERVIEW|FLOW_BULK_ELEMENT|FLOW_ELEMENT)/")
    vim.cmd("syntax match CalloutLog      /\\vCALLOUT/")
	vim.cmd("syntax match ApexLogException /\\vEXCEPTION/")
	vim.cmd("syntax match ApexLogOther     /\\v(EXECUTION|CODE_UNIT|ROOT)/")
	vim.cmd("syntax match ApexLogDuration  /\\v\\[[0-9.]+ms(\\|\\d*\\%)?\\]/")
    vim.cmd("syntax match LIMIT           /\\vLIMIT/")

	-- Link our syntax groups to standard, theme-aware highlight groups.
	vim.cmd("hi default link ApexLogMethod    Function")
	vim.cmd("hi default link ApexLogSOQL      Statement")
	vim.cmd("hi default link ApexLogDML       PreProc")
	vim.cmd("hi default link ApexLogException Error")
	vim.cmd("hi default link ApexLogOther     Constant")
	vim.cmd("hi default link ApexLogDuration  Comment")
    vim.cmd("hi default link FlowLog         Function")
    vim.cmd("hi default link CalloutLog      Function")
    vim.cmd("hi default link LIMIT           Comment")
end

-- The main function that generates the execution tree from a given log file path.
function M.generate_tree(log_path)
	-- Ensure a valid file path was provided.
	if not log_path or log_path == "" then
		vim.notify("No log file path provided or current buffer is not a file.", vim.log.levels.ERROR)
		return
	end

	vim.notify("Generating execution tree for: " .. log_path, vim.log.levels.INFO)

	-- Use plenary.job to run the command asynchronously.
	Job:new({
		-- We use 'bash -c' to properly handle the shell pipe (|).
		command = "bash",
		args = {
			"-c",
			-- Construct the full shell command, ensuring file paths and the script are properly escaped.
			"apex-log-parser -f "
				.. vim.fn.shellescape(log_path)
				.. " --tree",
		},
		-- This function is the callback that runs when the job completes.
		on_exit = function(j, return_val)
			-- All UI-related API calls must be wrapped in `vim.schedule` to run on the main thread.
			vim.schedule(function()
				-- Check if the command executed successfully.
				if return_val ~= 0 then
					vim.notify("Error generating log tree. Check logs for details.", vim.log.levels.ERROR)
					-- For debugging, you can print stderr to see what went wrong.
					local error_output = j:stderr_result()
					if error_output and #error_output > 0 then
						vim.notify(
							table.concat(error_output, "\n"),
							vim.log.levels.ERROR,
							{ title = "Apex Log Parser Error" }
						)
					end
					return
				end

				-- Get the output (stdout) from the completed job.
				local output = j:result()

				-- Construct a unique buffer name from the original log path.
				local tree_buf_name = vim.fn.fnamemodify(log_path, ":t") .. "-tree"
				local bufnr = vim.fn.bufnr(tree_buf_name)

				-- If the buffer doesn't exist, create it in a new split.
				if bufnr == -1 then
					vim.cmd("new") -- Always create a new horizontal split
					bufnr = vim.api.nvim_get_current_buf()
					vim.api.nvim_buf_set_name(bufnr, tree_buf_name)
					-- Set options for the new buffer
					vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
					vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
					vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
					vim.api.nvim_buf_set_option(bufnr, "filetype", "apexlogtree") -- Still useful for statusline, etc.
				else
					-- If buffer exists, find its window or open it in a new split.
					local winid = vim.fn.bufwinid(bufnr)
					if winid == -1 then
						vim.cmd("sbuffer " .. bufnr)
					else
						vim.api.nvim_set_current_win(winid)
					end
				end

				-- Update the buffer content.
				vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, output)
				vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
				-- Reset the modified flag so the buffer can be closed without a warning.
				vim.api.nvim_buf_set_option(bufnr, "modified", false)
				-- Apply the syntax highlighting directly.
				apply_syntax()

				vim.notify("Execution tree generated successfully!", vim.log.levels.INFO)
			end)
		end,
	}):start()
end

-- Setup function to create the user command.
function M.setup()
	-- Create a global user command `:ApexLogTree` that calls our function.
	vim.api.nvim_create_user_command("ApexLogTree", function()
		-- Get the path of the current buffer and pass it to the generate_tree function.
		local current_buf_path = vim.api.nvim_buf_get_name(0)
		M.generate_tree(current_buf_path)
	end, {
		nargs = 0,
		desc = "Generate an execution tree from the Apex log file in the current buffer.",
	})
end

return M
