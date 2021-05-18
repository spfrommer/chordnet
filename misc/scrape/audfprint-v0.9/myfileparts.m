function [p,n,e] = myfileparts(fn)
%  Replacement for fileparts that allows dots in file names...

[p,n,e] = fileparts(fn);
if length(e) > 5
  n = [n,e];
  e = '';
end
