local Job = require('plenary.job')

local M = {}

-- Local function to apply syntax highlighting directly to the current buffer.
local function apply_syntax()
  -- Define syntax matches for each event type using "very magic" regex.
  vim.cmd('syntax match ApexLogMethod    /\\vMETHOD/')
  vim.cmd('syntax match ApexLogSOQL      /\\vSOQL/')
  vim.cmd('syntax match ApexLogDML       /\\vDML/')
  vim.cmd('syntax match ApexLogException /\\vEXCEPTION/')
  vim.cmd('syntax match ApexLogOther     /\\v(EXECUTION|CODE UNIT|ROOT)/')
  vim.cmd('syntax match ApexLogDuration  /\\v\\[[0-9.]+ms(\\|\\d*\\%)?\\]/')

  -- Link our syntax groups to standard, theme-aware highlight groups.
  vim.cmd('hi default link ApexLogMethod    Function')
  vim.cmd('hi default link ApexLogSOQL      Statement')
  vim.cmd('hi default link ApexLogDML       PreProc')
  vim.cmd('hi default link ApexLogException Error')
  vim.cmd('hi default link ApexLogOther     Constant')
  vim.cmd('hi default link ApexLogDuration  Comment')
end

-- The main function that generates the execution tree from a given log file path.
function M.generate_tree(log_path)
  -- Ensure a valid file path was provided.
  if not log_path or log_path == '' then
    vim.notify('No log file path provided or current buffer is not a file.', vim.log.levels.ERROR)
    return
  end

  -- The jq script for parsing and formatting the log output.
  -- It's stored in a multiline string for clarity.
  local jq_script = [[
def duration_bar(ms; max_ms):
  if ms == null then "" else
    (ms / max_ms * 40) as $bar_length |
    ("█" * ($bar_length | floor))
  end;

def find_max_duration:
  [.. | select(type == "object" and has("durationMs")) | .durationMs] | max;

# A helper function to format the details of a single line.
def format_line(node; max_duration; total_duration):
    (node.type +
        (if node.name then " (" + node.name + ")" else "" end) +
        (if node.method then " (" + node.method + ")" else "" end) +
        (if node.type == "DML" and .operation and .object and .rows then " (" + node.operation + " on " + node.object + " - Rows: " + (node.rows | tostring) + ")" else "" end) +
        (if node.type == "SOQL" and .query then " (" + node.query + ")" else "" end) +
        (if node.durationMs then
          " [" + (node.durationMs | tostring) + "ms" +
          (if (total_duration | type) == "number" and total_duration > 0 then
            "|" + ((node.durationMs / total_duration * 100) | tostring | split(".")[0]) + "%"
          else "" end) +
          "] " +
          duration_bar(node.durationMs; max_duration)
        else "" end)
    );

# A single, robust recursive function to print a node and its children.
# Input: the node object.
# Arguments: indent string, is_last boolean, max_duration, total_duration
def print_node_recursive(indent; is_last; max_duration; total_duration):
    . as $node |
    # Determine the prefixes for the current line and for children
    (if is_last then indent + "└── " else indent + "├── " end) as $line_prefix |
    (if is_last then indent + "    " else indent + "│   " end) as $child_indent |

    # Output the current node's formatted line
    ($line_prefix + format_line($node; max_duration; total_duration)),

    # Recurse on children if they exist
    ($node.children? | if . and length > 0 then
        # Process all children except the last one
        (.[0:-1] | .[] | print_node_recursive($child_indent; false; max_duration; total_duration)),
        # Process the last child
        (.[-1] | print_node_recursive($child_indent; true; max_duration; total_duration))
    else empty end)
;


# --- Main execution ---
(.tree | find_max_duration) as $max |
.tree.durationMs as $total |

# 1. Print the root node itself (no indent or branch)
format_line(.tree; $max; $total),

# 2. Start the recursion for the root's children
(.tree.children? | if . and length > 0 then
    (.[0:-1] | .[] | print_node_recursive(""; false; $max; $total)),
    (.[-1] | print_node_recursive(""; true; $max; $total))
else empty end)
]]

  vim.notify('Generating execution tree for: ' .. log_path, vim.log.levels.INFO)

  -- Use plenary.job to run the command asynchronously.
  Job:new({
    -- We use 'bash -c' to properly handle the shell pipe (|).
    command = 'bash',
    args = {
      '-c',
      -- Construct the full shell command, ensuring file paths and the script are properly escaped.
      'apex-log-parser -f ' .. vim.fn.shellescape(log_path) .. ' | jq -r ' .. vim.fn.shellescape(jq_script)
    },
    -- This function is the callback that runs when the job completes.
    on_exit = function(j, return_val)
      -- All UI-related API calls must be wrapped in `vim.schedule` to run on the main thread.
      vim.schedule(function()
        -- Check if the command executed successfully.
        if return_val ~= 0 then
          vim.notify('Error generating log tree. Check logs for details.', vim.log.levels.ERROR)
          -- For debugging, you can print stderr to see what went wrong.
          local error_output = j:stderr_result()
          if error_output and #error_output > 0 then
            vim.notify(table.concat(error_output, "\n"), vim.log.levels.ERROR, { title = "Apex Log Parser Error" })
          end
          return
        end

        -- Get the output (stdout) from the completed job.
        local output = j:result()

        -- Construct a unique buffer name from the original log path.
        local tree_buf_name = vim.fn.fnamemodify(log_path, ':t') .. '-tree'
        local bufnr = vim.fn.bufnr(tree_buf_name)

        -- If the buffer doesn't exist, create it in a new split.
        if bufnr == -1 then
          vim.cmd('new') -- Always create a new horizontal split
          bufnr = vim.api.nvim_get_current_buf()
          vim.api.nvim_buf_set_name(bufnr, tree_buf_name)
          -- Set options for the new buffer
          vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
          vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'hide')
          vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
          vim.api.nvim_buf_set_option(bufnr, 'filetype', 'apexlogtree') -- Still useful for statusline, etc.
        else
          -- If buffer exists, find its window or open it in a new split.
          local winid = vim.fn.bufwinid(bufnr)
          if winid == -1 then
            vim.cmd('sbuffer ' .. bufnr)
          else
            vim.api.nvim_set_current_win(winid)
          end
        end

        -- Update the buffer content.
        vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, output)
        vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
        -- Reset the modified flag so the buffer can be closed without a warning.
        vim.api.nvim_buf_set_option(bufnr, 'modified', false)
        -- Apply the syntax highlighting directly.
        apply_syntax()

        vim.notify('Execution tree generated successfully!', vim.log.levels.INFO)
      end)
    end,
  }):start()
end

-- Setup function to create the user command.
function M.setup()
  -- Create a global user command `:ApexLogTree` that calls our function.
  vim.api.nvim_create_user_command('ApexLogTree', function()
    -- Get the path of the current buffer and pass it to the generate_tree function.
    local current_buf_path = vim.api.nvim_buf_get_name(0)
    M.generate_tree(current_buf_path)
  end, {
    nargs = 0,
    desc = "Generate an execution tree from the Apex log file in the current buffer."
  })
end

return M
