sub red($str) is export { "\e[31m" ~ $str ~ "\e[0m" }
sub green($str) is export { "\e[32m" ~ $str ~ "\e[0m" }
sub yellow($str) is export { "\e[33m" ~ $str ~ "\e[0m" }
sub blue($str) is export { "\e[36m" ~ $str ~ "\e[0m" }
