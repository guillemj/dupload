map m :!M 
map e :cf errors
map v :,/^-----END/w !pgp -m
map d :/^-----BEG/,/^-----END/!pgp -f
map s :,$!pgp -fast +clear
map e :,$!pgp -feast
set autoindent
set autowrite
set errorformat=%f:%l:%m
set mouse=n
set ruler
set shell=/bin/sh
set showmatch
set smartindent
set textwidth=71
