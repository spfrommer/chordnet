function rewrite_aligned_audio(inputname, outputname, offset, skew, maxdur)
% rewrite_audio(inputname, outputname, offset, skew, maxdur)
%    Read in a waveform; write out a new version such that the
%    output is the original *advanced* by <offset> (so -ve offset
%    introduces silence at the start of the output), and sped up by
%    factor <skew> (so skew > 1 leads to shorter output)
%     t_output = (t_input - offset) / skew
%    Optional maxdur will truncate the output at that duration.
% 2013-08-30 Dan Ellis dpwe@ee.columbia.edu
% adapted from deskew.m via skewview.m

if nargin < 3; offset = 0; end % then why are you calling me?
if nargin < 4; skew = 1; end
if nargin < 5; maxdur = 0; end

% re-read targ
[dr,sr] = audioread_custom(inputname);
if offset < 0
  % prepad silence
  dr = [zeros(round(-offset*sr),size(dr,2));dr];
  % is silence before or after time scaling?
else
  % -ve offset is time to trim from input file
  dr = dr(round(offset*sr)+1:end,:);
end
  
% Apply time scaling via resampling: 
% Find p/q s.t. p/q ~= a -- approx 1 part in 1/(a-1)
p0 = floor(1/abs(skew-1));
if p0 < 2^15
  % exhaustive search for pair of integers closest to desired rate
  p = p0:(2^15);
  q = round(p./skew);
  er = (skew - p./q); 
  [ee,xx] = min(abs(er));
%  disp(['Resampling ratio: ',sprintf('%d/%d=%.6f',p(xx),q(xx),p(xx)/q(xx))]);
  for i = 1:size(dr,2)
    dmr(:,i) = resample(dr(:,i),q(xx),p(xx));
  end
  dr = dmr;
end
% Maybe limit duration
if maxdur > 0
  dr = dr(1:min(round(maxdur*sr), size(dr,1)), :);
end
% Write it out
audiowrite(outputname,dr,sr);
disp(['Wrote skewed audio to ',outputname,' from ',inputname, ...
      ' with ',sprintf('offset=%.3fs skew=%.6f maxdur=%.1fs', ...
                       offset,skew,maxdur)]);

disp('Equivalent sox command:')
offsetstretch = offset/skew;
if offset < 0
  cmd = ['sox ', inputname, ' ', outputname, ' speed ', sprintf('%.6f', skew), ...
         ' delay ', num2str(-offsetstretch)];
  if size(dr,2) == 2
    % need to specify delay for both channels
    cmd = [cmd, ' ', num2str(-offsetstretch)];
  end
  if maxdur > 0
    cmd = [cmd, ' trim 0 ', num2str(maxdur)];
  end
else
  cmd = ['sox ', inputname, ' ', outputname, ' speed ', sprintf('%.6f', skew), ...
         ' trim ', num2str(offsetstretch)];
  if maxdur > 0
    cmd = [cmd, ' ', num2str(offsetstretch+maxdur)];
  end
end
disp(cmd);

