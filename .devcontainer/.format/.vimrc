" === 0. 加载 Vim 示例配置 ===
source $VIMRUNTIME/vimrc_example.vim


" === 1. 核心 Vim 设置 ===
filetype plugin indent on  " 开启文件类型检测、插件和缩进
syntax on                  " 打开语法高亮


" === 2. 编码设置 ===
set encoding=utf-8                                " Vim 内部编码
set fileencodings=utf-8,gb18030,gbk,gb2312,latin1 " 文件编码检测顺序


" === 3. 跨端剪贴板桥接 ===
if !has('win32') && !has('win64') 
    \ && filereadable('/proc/version') 
    \ && readfile('/proc/version', '', 1)[0] =~# 'microsoft'
    \ && has('clipboard_provider')

    if executable('wl-copy') && executable('wl-paste')
        func! WslClipAvailable() abort
            return v:true
        endfunc

        func! WslClipCopy(reg, type, str) abort
            let l:args = 'wl-copy'
            if a:reg ==# '*'
                let l:args .= ' -p'
            endif
            call system(l:args, a:str)
        endfunc

        func! WslClipPaste(reg) abort
            let l:args = 'wl-paste --type text/plain;charset=utf-8'
            if a:reg ==# '*'
                let l:args .= ' -p'
            endif
            return ['', systemlist(l:args)]
        endfunc

        let v:clipproviders["wl_clipboard"] = {
              \ 'available': function('WslClipAvailable'),
              \ 'copy': {
              \   '+': function('WslClipCopy'),
              \   '*': function('WslClipCopy'),
              \ },
              \ 'paste': {
              \   '+': function('WslClipPaste'),
              \   '*': function('WslClipPaste'),
              \ }
              \ }

        set clipmethod=wl_clipboard
        set clipboard=unnamedplus
    endif
endif


" === 4. 文件处理与备份 ===
set nobackup               " 覆盖文件时不备份
set nowritebackup          " 建议: set writebackup (更安全, 但g设置了nobackup)
set noundofile             " 不使用撤销文件 (个人偏好，若需持久撤销则 set undofile)
set autoread               " 当文件在外部被修改时自动重新读取
set autochdir              " 自动切换当前目录到正在编辑的文件所在的目录


" === 5. 用户界面与体验 ===
set number                 " 在左侧显示行号
set ruler                  " 显示光标当前位置的行号和列号
set showcmd                " 在状态栏显示部分命令
set showmode               " 在底部显示当前模式 (Normal, Insert 等)
set laststatus=2           " 始终显示状态栏
set cursorline             " 高亮当前行
set shortmess=atI          " 启动时不显示欢迎信息，减少提示
set report=0               " 命令执行后报告改变的行数 (0表示总是报告)
set scrolloff=3            " 光标上下移动时，距离窗口顶部/底部的最小行数
set sidescrolloff=5        " 可选: 水平滚动时保留的列数
set history=1000           " 设置命令历史记录的大小
set confirm                " 在处理未保存或只读文件的时候，弹出确认
set mouse=a                " 在所有模式下启用鼠标
set helplang=cn            " 设置帮助语言为中文


" === 6. 编辑行为 ===
set autoindent                 " 新行自动继承上一行的缩进
set smartindent                " 更智能的缩进 (对C类语言有效)
set tabstop=4                  " Tab 字符在屏幕上显示的宽度 (空格数)
set shiftwidth=4               " 自动缩进 (`>>`, `<<`) 时使用的空格数
set softtabstop=4              " 按 Tab/Backspace 时操作的空格数 (当 expandtab 时模拟 Tab)
set noexpandtab                " 按 Tab 键时插入实际的 Tab 字符 (而不是空格)
set smarttab                   " 在行首按 Tab 时根据 shiftwidth 插入 Tab，而不是 tabstop (此选项在 noexpandtab 时更有意义)
set hlsearch                   " 高亮所有搜索匹配项
set incsearch                  " 输入搜索模式时，实时高亮匹配项
set ignorecase                 " 搜索时忽略大小写
set smartcase                  " 如果搜索模式中包含大写字母，则进行大小写敏感搜索
set wrapscan                   " 允许搜索时从文件末尾回绕到开头
set showmatch                  " 短暂跳转到匹配的括号
set matchtime=5                " 匹配括号高亮时间 (十分之一秒)
set wildmenu                   " 启用命令模式下的补全菜单
set wildmode=longest:list,full " Tab补全行为
set backspace=indent,eol,start " 退格键行为 (2 等价于 indent,eol,start 的一个子集)
set iskeyword+=_,$,@,%,#,-     " 带有这些符号的单词视作一个整体
set gdefault                   " 替换时默认全局 (`s/foo/bar/` 等同于 `s/foo/bar/g`)
set wrap                       " 自动换行长行
set linebreak                  " 如果换行，则在单词边界处换行 (配合 wrap 使用)


" === 7. Diff 功能设置 ===
if &diffopt !~# 'internal'
	set diffexpr=s:MyDiff()
endif

function! s:MyDiff()
	let opt = '-a --binary '
	if &diffopt =~ 'icase' | let opt = opt . '-i ' | endif
	if &diffopt =~ 'iwhite' | let opt = opt . '-b ' | endif
	let arg1 = v:fname_in
	if arg1 =~ ' ' | let arg1 = '"' . arg1 . '"' | endif
	let arg1 = substitute(arg1, '!', '\!', 'g')
	let arg2 = v:fname_new
	if arg2 =~ ' ' | let arg2 = '"' . arg2 . '"' | endif
	let arg2 = substitute(arg2, '!', '\!', 'g')
	let arg3 = v:fname_out
	if arg3 =~ ' ' | let arg3 = '"' . arg3 . '"' | endif
	let arg3 = substitute(arg3, '!', '\!', 'g')
	let cmd = ''
	if $VIMRUNTIME =~ ' '
		if &shell =~ '\<cmd' && empty(&shellxquote)
			let s:shxq_sav = &shellxquote
			set shellxquote=\"
			let cmd = '"' . $VIMRUNTIME . '\diff"'
		else
			let cmd = escape($VIMRUNTIME, ' ') . '\diff'
		endif
	else
		let cmd = $VIMRUNTIME . '\diff'
	endif
	let cmd = substitute(cmd, '!', '\!', 'g')

	silent execute '!' . cmd . ' ' . opt . arg1 . ' ' . arg2 . ' > ' . arg3
	if exists('s:shxq_sav')
		let &shellxquote = s:shxq_sav
		unlet s:shxq_sav
	endif

	redraw!
endfunction


" === 8. 状态栏设置 ===
set statusline=\ %F%m%r%h%w\ [Format=%{&ff}]\ [Type=%Y]\ %=\ [行:%l,\ 列:%v,\ 位置:%p%%]


" === 9. Gvim 特定设置 ===
if has('gui_running')
	set langmenu=zh_CN.UTF-8
	set guicursor=a:ver25-Cursor/lCursor
endif


" === 10. 自定义映射与缩写 ===
inoremap ' ''<Left>
inoremap " ""<Left>
inoremap ( ()<Left>
inoremap [ []<Left>
inoremap { {}<Left>
inoremap < <><Left>


" === 11. 终端特定设置 ===
if !has('gui_running')
	" set t_Co=256
	" if &t_Co == 256
	" 	colorscheme solarized8_dark "
	" endif
endif

highlight CursorLine cterm=NONE ctermbg=153 guibg=#BFE4FF                  " 高亮当前行
highlight CursorLineNr cterm=NONE ctermfg=Yellow ctermbg=153 guibg=#BFE4FF " 高亮当前行号


" === 12. 自动创建不存在的父目录 ===
augroup AutoCreateDirs
	autocmd!
	autocmd BufWritePre * call s:EnsureParentDirExists()
augroup END

function! s:EnsureParentDirExists()
	let l:dir = expand('<afile>:p:h')
	if !isdirectory(l:dir)
		call mkdir(l:dir, 'p', 0755)
		echo "已创建目录：" . l:dir
	endif
endfunction

" === 13. 强制终端光标设置 ===
if !has('gui_running')
    let &t_SI = "\e[5 q"
    let &t_EI = "\e[5 q"
    let &t_SR = "\e[5 q"
    let &t_RS = "\e[5 q"
endif

" === 14. 使用 fzf 在 vim ===
set rtp+=/home/linuxbrew/.linuxbrew/opt/fzf

