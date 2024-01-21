local M = {}

local defaults = {
  default = {
    debug = false, -- enable debug mode
    dir_path = "assets", -- directory path to save images to, can be relative (cwd or current file) or absolute
    file_name = "%Y-%m-%d-%H-%M-%S", -- file name format (see lua.org/pil/22.1.html)
    url_encode_path = false, -- encode spaces and special characters in file path
    use_absolute_path = false, -- expands dir_path to an absolute path
    relative_to_current_file = false, -- make dir_path relative to current file rather than the cwd
    relative_template_path = true, -- make file path in the template relative to current file rather than the cwd
    prompt_for_file_name = true, -- ask user for file name before saving, leave empty to use default
    show_dir_path_in_prompt = false, -- show dir_path in prompt when prompting for file name
    use_cursor_in_template = true, -- jump to cursor position in template after pasting
    insert_mode_after_paste = true, -- enter insert mode after pasting the markup code
    embed_image_as_base64 = false, -- paste image as base64 string instead of saving to file
    max_base64_size = 10, -- max size of base64 string in KB
    template = "$FILE_PATH", -- default template

    drag_and_drop = {
      enabled = true, -- enable drag and drop mode
      insert_mode = false, -- enable drag and drop in insert mode
      copy_images = false, -- copy images instead of using the original file
      download_images = true, -- download images and save them to dir_path instead of using the URL
    },
  },

  -- file-type specific opts
  -- any opts that are passed here will override the default config
  -- for instance, setting use_absolute_path = true for markdown will
  -- only enable that for this particular file type
  -- the key (e.g. "markdown") is the filetype (output of "set filetype?")
  filetypes = {
    markdown = {
      url_encode_path = true,
      template = "![$CURSOR]($FILE_PATH)",

      drag_and_drop = {
        download_images = false,
      },
    },

    html = {
      template = '<img src="$FILE_PATH" alt="$CURSOR">',
    },

    tex = {
      relative_template_path = false,
      template = [[
\begin{figure}[h]
  \centering
  \includegraphics[width=0.8\textwidth]{$FILE_PATH}
  \caption{$CURSOR}
  \label{fig:$LABEL}
\end{figure}
    ]],
    },

    typst = {
      template = [[
#figure(
  image("$FILE_PATH", width: 80%),
  caption: [$CURSOR],
) <fig-$LABEL>
    ]],
    },

    rst = {
      template = [[
.. image:: $FILE_PATH
   :alt: $CURSOR
   :width: 80%
    ]],
    },

    asciidoc = {
      template = 'image::$FILE_PATH[width=80%, alt="$CURSOR"]',
    },

    org = {
      template = [=[
#+BEGIN_FIGURE
[[file:$FILE_PATH]]
#+CAPTION: $CURSOR
#+NAME: fig:$LABEL
#+END_FIGURE
    ]=],
    },
  },
}

defaults.filetypes.plaintex = defaults.filetypes.tex
defaults.filetypes.rmd = defaults.filetypes.markdown
defaults.filetypes.md = defaults.filetypes.markdown

---Recursively gets the value of the option (e.g. "default.debug")
---@param key string
---@param opts table
---@return string | nil
local function recursive_get_opt(key, opts)
  local keys = vim.split(key, ".", { plain = true, trimempty = true })

  for _, k in pairs(keys) do
    if opts and opts[k] ~= nil then
      opts = opts[k]
    else
      return nil -- option not found in this table
    end
  end
  return opts
end

---Gets the value of the option, executing it if it's a function
---@param val any
---@param args? table
---@return string | nil
local function get_val(val, args)
  if val == nil then
    return nil
  else
    return type(val) == "function" and val(args or {}) or val
  end
end

---Gets the option from the custom table
---@param key string
---@param opts table
---@param args table
---@return string | nil
local function get_custom_opt(key, opts, args)
  if opts["custom"] == nil then
    return nil
  end

  for _, config_opts in pairs(opts["custom"]) do
    if config_opts["trigger"] and get_val(config_opts["trigger"]) then
      local M_opts = M.opts
      M.opts = config_opts

      local val = M.get_opt(key, {}, args)
      if val then
        return val
      end

      M.opts = M_opts
      return nil
    end
  end
end

---Gets the option from the files table
---@param key string
---@param opts table
---@param args table
---@return string | nil
local function get_file_opt(key, opts, args, file)
  if opts["files"] == nil then
    return nil
  end

  for config_file, config_file_opts in pairs(opts["files"]) do
    if file:sub(-#config_file) == config_file then
      local M_opts = M.opts
      M.opts = config_file_opts

      local val = M.get_opt(key, {}, args)
      if val then
        return val
      end

      M.opts = M_opts
      return nil
    end
  end
end

---Gets the option from the dirs table
---@param key string
---@param opts table
---@param args table
---@return string | nil
local function get_dir_opt(key, opts, args, dir)
  if opts["dirs"] == nil then
    return nil
  end

  for config_dir, config_dir_opts in pairs(opts["dirs"]) do
    if dir:sub(1, #config_dir) == config_dir then
      local M_opts = M.opts
      M.opts = config_dir_opts

      local val = M.get_opt(key, {}, args)
      if val then
        return val
      end

      M.opts = M_opts
      return nil
    end
  end
end

---Gets the option from the filetypes table
---@param key string
---@param opts table
---@return string | nil
local function get_filetype_opt(key, opts, ft)
  return recursive_get_opt("filetypes." .. ft .. "." .. key, opts)
end

---Gets the option from the default table
---@param key string
---@param opts table
---@return string | nil
local function get_default_opt(key, opts)
  return recursive_get_opt("default." .. key, opts)
end

M.opts = {}

---@param key string The key, may be nested (e.g. "default.debug")
---@param api_opts? table The opts passed to pasteImage function
---@return string | nil
M.get_opt = function(key, api_opts, args)
  local opts = vim.tbl_deep_extend("force", {}, M.opts, api_opts or {})

  local val = get_custom_opt(key, opts, args)
    or get_file_opt(key, opts, args, vim.fn.expand("%:p"))
    or get_file_opt(key, opts, args, vim.fn.expand("%:p:t"))
    or get_dir_opt(key, opts, args, vim.fn.expand("%:p:h"))
    or get_dir_opt(key, opts, args, vim.fn.expand("%:p:h:t"))
    or get_filetype_opt(key, opts, vim.bo.filetype)
    or get_default_opt(key, opts)

  return get_val(val, args)
end

function M.setup(config_opts)
  M.opts = vim.tbl_deep_extend("force", {}, defaults, config_opts or {})
end

return M
