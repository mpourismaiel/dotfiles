call plug#begin('~/.vim/plugged')

Plug 'dracula/vim', { 'as': 'dracula' }
Plug 'tomtom/tcomment_vim'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-fugitive'
Plug 'preservim/nerdtree'
Plug '~/.fzf'
Plug 'junegunn/fzf.vim'
Plug 'airblade/vim-gitgutter'
Plug 'yggdroot/indentline'
Plug 'godlygeek/tabular'
Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'Shougo/vimproc.vim', {'do' : 'make'}
Plug 'TaDaa/vimade'
Plug 'jeetsukumaran/vim-buffergator'
Plug 'junegunn/goyo.vim'
Plug 'bling/vim-bufferline'
Plug 'myusuf3/numbers.vim'
Plug 'mhinz/vim-startify'
Plug 'google/vim-searchindex'
Plug 'gcmt/taboo.vim'
Plug 'farmergreg/vim-lastplace'
Plug 'plasticboy/vim-markdown'
Plug 'dense-analysis/ale'
Plug 'Asheq/close-buffers.vim'
Plug 'junegunn/vim-github-dashboard'
Plug 'valloric/youcompleteme'
Plug 'duff/vim-scratch'
Plug 'eliba2/vim-node-inspect'
Plug 'vim-scripts/AfterColors.vim'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'

call plug#end()
