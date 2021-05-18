function [N,T,H,thop] = add_tracks_byname(D, TSKIP, TDUR, dens, matchthresh, THOPI, TARGETSR, quiet, basenum)
% [N,T,H,thop] = add_tracks_byname(D, TSKIP, TDUR, dens, matchthresh, THOPI, TARGETSR, quiet, basenum)
%    Add audio files to the hashtable database.  
%    D is a cell array of paths to audio files.
%    dens is hash density per second (default 7).
%    TSKIP > 0 drops that many seconds of sound from the start of
%    each file read, then TDUR truncates to at most that time.
%    matchthresh > 0 tries to match the item before adding it, and
%    skips it if it has >= matchthresh hashes in common with an
%    existing ref item.
%    THOPI is the requested STFT time resolution in sec.  0 means
%    default in find_landmarks .
%    TARGETSR is the SR for find_landmarks (11025)
%    quiet as 1 suppresses messages.
%    basenum, if present, is added to the "file number" counts
%    reported to the terminal.
%
%    N returns the total number of hashes added, T returns total
%    duration in secs of tracks added.
%
% 2011-12-01 Dan Ellis dpwe@ee.columbia.edu

if nargin < 2;  TSKIP = 0; end
if nargin < 3;  TDUR = 0; end

% Target query landmark density
% (reference is 7 lm/s)
if nargin < 4; dens = 7; end
disp(['Target density = ',num2str(dens),' hashes/sec']);

if nargin < 5; matchthresh = 0; end
if nargin < 6; THOPI = 0; end
if nargin < 7; TARGETSR = 11025; end
if nargin < 8; quiet = 0; end
if nargin < 9; basenum = 0; end

tstart = tic;

nd = length(D);
N = 0;
T = 0;
H = [];
thop = 0;

for i = 1:nd
  F = D{i};

  if ~quiet
    fprintf(1, [datestr(now()),' Adding #',num2str(i+basenum),' ',F,'...']);
  end

  targetsr = 11025;
  forcemono = 1;
  [d,sr] = audioread_custom(F,targetsr,forcemono,TSKIP,TDUR);
%  maxdur = 1200;  % truncate at 20 min
%  actdur = length(d)/sr;
%  if actdur > maxdur
%    if ~quiet
%      disp(['truncating ',F,' (dur ',sprintf('%.1f',actdur),' s) at ', ...
%            num2str(maxdur),' s']);
%    end
%    d = d(1:(maxdur*sr),:);
%  end
  
  if length(d) == 0
    H = [];
    n = 0;
    t = 0;
    thop = 0;
  else
    
    oversamp = 1;
    [LM,thop] = find_landmarks(d,sr,dens,THOPI,oversamp,TARGETSR);
    H = landmark2hash(LM);

    if matchthresh > 0
      % test match first
      matchminprop = 0;
      matchmaxret = 1;
      matchrawcounts = 0;
      maxtofilter = 100;
      matchwidth = 1;
      matchalign = 0;
      matchquiet = 0;
      warpmax = 0;
      warpstep = 0.001;
      R = match_query_hashes(H, matchthresh-1, matchminprop, ...
                             matchmaxret, matchrawcounts, ...
                             maxtofilter, matchwidth, ...
                             matchalign, ...
                             warpmax, warpstep, ...
                             matchquiet);
      oktoadd = (size(R,1) == 0);
    else
      oktoadd = 1;
    end
    
    if oktoadd
      ht_store(H,F);
      n = length(H);
      t = length(d)/sr;
    else
      if ~quiet
        disp(' ');
        disp(['*** skipping ', F, ' - matched to ', ht_name(R(1,1))]);
      end
      n = 0;
      t = 0;
    end
  
  end
  
  N = N + n;
  T = T + t;

  if ~quiet
    fprintf(1,'%.1f s, %d hashes\n', t, n);
  end

end

clocktime = toc(tstart);

if ~quiet
  disp(['added ',num2str(nd),' tracks (',num2str(T),' secs, ', ...
        num2str(N),' hashes, ',num2str(N/T),' hashes/sec)', ...
        ' in ',sprintf('%.1f',clocktime),' sec', ...
        ' = ',sprintf('%.3f',clocktime/T),' x RT']);
end



