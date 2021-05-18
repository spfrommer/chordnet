function [newfiles,dirfilesout] = check_for_new_files(dir, dirfilesin, ...
                                                  wait, bydate)
% [newfiles,dirfilesout] = check_for_new_files(dir, dirfilesin, wait, bydate)
% Wait for new files to appear in a directory and return their
% names.
% 2012-05-29 Dan Ellis dpwe@ee.columbia.edu

if nargin < 3; wait = 1; end
if nargin < 4; bydate = 0; end

newfiles = [];
done = 0;
while ~done
  pause(1);
  dirfilesout = myls(dir, bydate);
  newfiles = setdiff(dirfilesout, dirfilesin);
  dirfilesin = dirfilesout;  % not needed, but feels better
  done = (wait == 0) || (length(newfiles) > 0);
end
% Make sure we return the actual path to the new files
%for i = 1:length(newfiles)
%  newfiles{i} = fullfile(dir, newfiles{i});
%end
% myls does this OK
