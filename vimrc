let g:ale_cpp_clangd_executable = "/cheriot-tools/bin/clangd"
let g:ale_c_clangformat_executable = "/cheriot-tools/bin/clang-format"
let g:ale_cpp_cc_executable = "/cheriot-tools/bin/clang++"

let g:ale_fixers = {
\ 'cpp': ['clang-format'],
\ 'c': ['clang-format']
\}

let g:ale_linters = {
\ 'cpp': ['clangd'],
\ 'c': ['clangd']
\}

call plug#begin("~/.vim/plugged")
Plug 'dense-analysis/ale'
Plug 'vim-airline/vim-airline'
call plug#end()

packloadall
silent! helptags ALL

set omnifunc=ale#completion#OmniFunc

