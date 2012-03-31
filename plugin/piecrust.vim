" piecrust.vim - PieCrust plugin for Vim
" Maintainer:    Ludovic Chabant <http://ludovic.chabant.com>
" Version:       0.1

" Globals {{{

if !exists('g:piecrust_debug')
    let g:piecrust_debug = 0
endif

if (exists('g:loaded_piecrust') || &cp) && !g:piecrust_debug
    finish
endif
if (exists('g:loaded_piecrust') && g:piecrust_debug)
    echom "Reloaded PieCrust."
endif
let g:loaded_piecrust = 1

if !exists('g:piecrust_chef_executable')
    let g:piecrust_chef_executable = 'chef'
endif

if !exists('g:piecrust_trace')
    let g:piecrust_trace = 0
endif

" }}}

" Utility {{{

" Strips the ending slash in a path.
function! s:stripslash(path)
    return fnamemodify(a:path, ':s?[/\\]$??')
endfunction

" Normalizes the slashes in a path.
function! s:normalizepath(path)
    if exists('+shellslash') && &shellslash
        return substitute(a:path, '\\', '/', '')
    elseif has('win32')
        return substitute(a:path, '/', '\\', '')
    else
        return a:path
    endif
endfunction

" Prints a message if debug tracing is enabled.
function! s:trace(message, ...)
   if g:piecrust_trace || (a:0 && a:1)
       let l:message = "piecrust: " . a:message
       echom l:message
   endif
endfunction

" Prints an error message with 'piecrust error' prefixed to it.
function! s:error(message)
    echom "piecrust error: " . a:message
endfunction

" Throw a PieCrust exception message.
function! s:throw(message)
    let v:errmsg = "piecrust: " . a:message
    throw v:errmsg
endfunction

" Finds the website root given a path inside that website.
" Throw an error if not repository is found.
function! s:find_website_root(path)
    let l:path = s:stripslash(a:path)
    let l:previous_path = ""
    while l:path != l:previous_path
        if filereadable(l:path . '/_content/config.yml')
            return simplify(fnamemodify(l:path, ':p'))
        endif
        let l:previous_path = l:path
        let l:path = fnamemodify(l:path, ':h')
    endwhile
    call s:throw("No PieCrust website found above: " . a:path)
endfunction

" }}}

" PieCrust website {{{

" Let's define a PieCrust website 'class' using prototype-based object-oriented
" programming.
"
" The prototype dictionary.
let s:PieCrust = {}

" Constructor
function! s:PieCrust.New(path) abort
    let l:newSite = copy(self)
    let l:newSite.root_dir = s:find_website_root(a:path)
    call s:trace("Built new PieCrust website object at : " . l:newSite.root_dir)
    return l:newSite
endfunction

" Gets a full path given a repo-relative path
function! s:PieCrust.GetFullPath(path) abort
    let l:root_dir = self.root_dir
    if a:path =~# '\v^[/\\]'
        let l:root_dir = s:stripslash(l:root_dir)
    endif
    return l:root_dir . a:path
endfunction

" Runs a Chef command in the website
function! s:PieCrust.RunCommand(command, ...) abort
    " If there's only one argument, and it's a list, then use that as the
    " argument list.
    let l:arg_list = a:000
    if a:0 == 1 && type(a:1) == type([])
        let l:arg_list = a:1
    endif
    let l:chef_command = g:piecrust_chef_executable . ' ' . a:command
    let l:chef_command = l:chef_command . ' --root=' . shellescape(s:stripslash(self.root_dir))
    let l:chef_command = l:chef_command . ' ' . join(l:arg_list, ' ')
    call s:trace("Running Chef command: " . l:chef_command)
    return system(l:chef_command)
endfunction

" Website cache map
let s:buffer_websites = {}

" Get a cached website
function! s:piecrust_website(...) abort
    " Use the given path, or the website directory of the current buffer.
    if a:0 == 0
        if exists('b:piecrust_dir')
            let l:path = b:piecrust_dir
        else
            let l:path = s:find_website_root(expand('%:p'))
        endif
    else
        let l:path = a:1
    endif
    " Find a cache website instance, or make a new one.
    if has_key(s:buffer_websites, l:path)
        return get(s:buffer_websites, l:path)
    else
        let l:website = s:PieCrust.New(l:path)
        let s:buffer_websites[l:path] = l:website
        return l:website
    endif
endfunction

" Sets up the current buffer with PieCrust commands if it contains a file from a PieCrust website.
" If the file is not in a PieCrust website, just exit silently.
function! s:setup_buffer_commands() abort
    call s:trace("Scanning buffer '" . bufname('%') . "' for PieCrust setup...")
    let l:do_setup = 1
    if exists('b:piecrust_dir')
        if b:piecrust_dir =~# '\v^\s*$'
            unlet b:piecrust_dir
        else
            let l:do_setup = 0
        endif
    endif
    try
        let l:website = s:piecrust_website()
    catch /^piecrust\:/
        return
    endtry
    let b:piecrust_dir = l:website.root_dir
    if exists('b:piecrust_dir') && l:do_setup
        call s:trace("Setting PieCrust commands for buffer '" . bufname('%'))
        call s:trace("  with website : " . expand(b:piecrust_dir))
        silent doautocmd User PieCrust
    endif
endfunction

augroup piecrust_detect
    autocmd!
    autocmd BufNewFile,BufReadPost *     call s:setup_buffer_commands()
    autocmd VimEnter               *     if expand('<amatch>')==''|call s:setup_buffer_commands()|endif
augroup end

" }}}

" Buffer Commands Management {{{

" Store the commands for PieCrust-enabled buffers so that we can add them in
" batch when we need to.
let s:main_commands = []

function! s:AddMainCommand(command) abort
    let s:main_commands += [a:command]
endfunction

function! s:DefineMainCommands()
    for l:command in s:main_commands
        execute 'command! -buffer ' . l:command
    endfor
endfunction

augroup piecrust_main
    autocmd!
    autocmd User PieCrust call s:DefineMainCommands()
augroup end

" }}}

" Pcedit {{{

function! s:PcEdit(bang, filename) abort
    let l:full_path = s:piecrust_website().GetFullPath(a:filename)
    if a:bang
        execute "edit! " . l:full_path
    else
        execute "edit " . l:full_path
    endif
endfunction

function! s:FindWebsiteFiles(ArgLead, CmdLine, CursorPos) abort
    let l:website = s:piecrust_website()
    let l:output = l:website.RunCommand('find', a:ArgLead)
    let l:matches = split(l:output, '\n')
    call map(l:matches, 's:normalizepath(v:val)')
    return l:matches
endfunction

call s:AddMainCommand("-bang -nargs=? -complete=customlist,s:FindWebsiteFiles Pcedit :call s:PcEdit(<bang>0, <f-args>)")

" }}}

" Autoload Functions {{{

" Rescans the current buffer for setting up PieCrust commands.
" Passing '1' as the parameter enables debug traces temporarily.
function! piecrust#rescan(...)
    if exists('b:piecrust_dir')
        unlet b:piecrust_dir
    endif
    if a:0 && a:1
        let l:trace_backup = g:piecrust_trace
        let g:piecrust_trace = 1
    endif
    call s:setup_buffer_commands()
    if a:0 && a:1
        let g:piecrust_trace = l:trace_backup
    endif
endfunction

" Enables/disables the debug trace.
function! piecrust#debugtrace(...)
    let g:piecrust_trace = (a:0 == 0 || (a:0 && a:1))
    echom "PieCrust debug trace is now " . (g:piecrust_trace ? "enabled." : "disabled.")
endfunction

" }}}
