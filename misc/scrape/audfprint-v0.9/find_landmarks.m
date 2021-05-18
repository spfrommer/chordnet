function [L,thop,S,T,maxes] = find_landmarks(D,SR,N,THOP,OVERSAMP,TARGETSR)
% [L,thop,S,T,maxes] = find_landmarks(D,SR,N,THOP,OVERSAMP,TARGETSR)
%   Make a set of spectral feature pair landmarks from some audio data
%   D is an audio waveform at sampling rate SR
%   L returns as a set of landmarks, as rows of a 4-column matrix
%   {start-time-col start-freq-row end-freq-row delta-time}
%   thop is the frame period of the analysis (0.02322, quantized to SR)
%   N is the target hashes-per-sec (approximately; default 5)
%   S returns the filtered log-magnitude surface
%   T returns the decaying threshold surface
%   maxes returns a list of the actual time-frequency peaks extracted.
%   OVERSAMP causes the grid to be inter-sampled by a factor
%   THOP sets the grid for the STFT - 0.02322 by default
%   TARGETSR is the sampling rate that audio is resampled to (11025)
%
%  REVISED VERSION FINDS PEAKS INCREMENTALLY IN TIME WITH DECAYING THRESHOLD
% 
% 2008-12-13 Dan Ellis dpwe@ee.columbia.edu

if nargin < 3;  N = 7;  end % 7 to get a_dec = 0.998
if nargin < 4;  THOP = 0;  end
if nargin < 5;  OVERSAMP = 0;  end
if nargin < 6;  TARGETSR = 11025;  end

% To resume pre-v0.9 behavior:
%BACKWARDS_COMPATIBLE = 1
BACKWARDS_COMPATIBLE = 0;
if BACKWARDS_COMPATIBLE
  if THOP == 0;  THOP = 0.032;  end  % default
else
  if THOP == 0;  THOP = 0.02322;  end  % 256/11025
  % THOP was 0.032 until v0.9, but this a weird n_hop = 353 samps
  % for 11025 Hz SR.  0.02322 gives nhop=256
end

if OVERSAMP == 0; OVERSAMP = 1; end

% The scheme relies on just a few landmarks being common to both
% query and reference items.  The greater the density of landmarks,
% the more like this is to occur (meaning that shorter and noisier
% queries can be tolerated), but the greater the load on the
% database holding the hashes.
%
% The factors influencing the number of landmarks returned are:
%  A.  The number of local maxima found, which in turn depends on 
%    A.1 The spreading width applied to the masking skirt from each
%        found peak (gaussian half-width in frequency bins).  A
%        larger value means fewer peaks found.
f_sd = 30;

%    A.2 The decay rate of the masking skirt behind each peak
%        (proportion per frame).  A value closer to one means fewer
%        peaks found.
%a_dec = 0.998;
a_dec = (1-0.01*(N*sqrt(THOP/0.032)/35))^(1/OVERSAMP);
% 0.999 -> 2.5
% 0.998 -> 5 hash/sec
% 0.997 -> 10 hash/sec
% 0.996 -> 14 hash/sec
% 0.995 -> 18
% 0.994 -> 22
% 0.993 -> 27
% 0.992 -> 30
% 0.991 -> 33
% 0.990 -> 37
% 0.98  -> 67
% 0.97  -> 97



%    A.3 The maximum number of peaks allowed for each frame.  In
%        practice, this is rarely reached, since most peaks fall
%        below the masking skirt
maxpksperframe = 5;

%    A.4 The high-pass filter applied to the log-magnitude
%        envelope, which is parameterized by the position of the
%        single real pole.  A pole close to +1.0 results in a
%        relatively flat high-pass filter that just removes very
%        slowly varying parts; a pole closer to -1.0 introduces
%        increasingly extreme emphasis of rapid variations, which
%        leads to more peaks initially.
hpf_pole = 0.98;

%  B. The number of pairs made with each peak.  All maxes within a
%     "target region" following the seed max are made into pairs,
%     so the larger this region is (in time and frequency), the
%     more maxes there will be.  The target region is defined by a
%     freqency half-width (in bins)
targetdf = 31;  % +/- 50 bins in freq (LIMITED TO -32..31 IN LANDMARK2HASH)

%     .. and a time duration (maximum look ahead)
targetdt = 63;  % (LIMITED TO <64 IN LANDMARK2HASH)

%     The actual frequency and time differences are quantized and
%     packed into the final hash; if they exceed the limited size
%     described above, the hashes become irreversible (aliased);
%     however, in most cases they still work (since they are
%     handled the same way for query and reference).


verbose = 0;

%targetSR = 8000;
%targetSR = 11025;
targetSR = TARGETSR;

% Maybe read a file
if ischar(D)
  fname = D;
  domono = 1;
  [D,sr] = audioread_custom(fname,targetsr, domono);
else
  fname = '<waveform>';
end


% Convert D to a mono row-vector
[nr,nc] = size(D);
if nr > nc
  D = D';
  [nr,nc] = size(D);
end
if nr > 1
  D = mean(D);
  nr = 1;
end

% Kick out empty sounds
if length(D) == 0
  L = [];
  S = [];
  T = [];
  maxes = [];
  return
end

% Resample to target sampling rate
if (SR ~= targetSR)
  D = resample(D,targetSR,SR);
end

% Take spectral features
% We use a 64 ms window (512 point FFT) for good spectral resolution
%fft_ms = 64;
if BACKWARDS_COMPATIBLE
  % This was the original line:
  fft_ms = round(512/(targetSR/1000));  % actually 46.4 ms for 11025 Hz SR
  % It made sense (or at least was not harmful) when the targetSR
  % was 16 kHz, and so the FFT window for a power-of-two window
  % size would be an integral number of ms.  But it was a bad move
  % for 11 kHz, since it gave us 46.0 ms windows, which led to nfft
  % nfft = 507 (= 3 x 13 x 13), not a good size for the FFT.
else
  fft_ms = (512/(targetSR/1000));  % 46.4 ms for 11025 Hz SR
  % Results in nfft = 512
end
%fft_hop = 32/OVERSAMP;
fft_hop = 1000*THOP/OVERSAMP;
nfft = round(targetSR/1000*fft_ms);
nhop = round(targetSR/1000*fft_hop);
thop = nhop / targetSR;
S = abs(specgram(D,nfft,targetSR,nfft,nfft-nhop));
% convert to log domain, and emphasize onsets
Smax = max(S(:));
% Work on the log-magnitude surface
S = log(max(Smax/1e6,S));
% Make it zero-mean, so the start-up transients for the filter are
% minimized
S = S - mean(S(:));
% This is just a high pass filter, applied in the log-magnitude
% domain.  It blocks slowly-varying terms (like an AGC), but also 
% emphasizes onsets.  Placing the pole closer to the unit circle 
% (i.e. making the -.8 closer to -1) reduces the onset emphasis.
S = (filter([1 -1],[1 -(hpf_pole^(1/OVERSAMP))],S')');


% Estimate for how many maxes we keep - < 30/sec (to preallocate array)
maxespersec = 30;

ddur = length(D)/targetSR;
nmaxkeep = round(maxespersec * ddur);
maxes = zeros(3,nmaxkeep);
nmaxes = 0;
maxix = 0;

%%%%% 
%% find all the local prominent peaks, store as maxes(i,:) = [t,f];

%% overmasking factor?  Currently none.
s_sup = 1.0;

% initial threshold envelope based on peaks in first 10 frames
sthresh = s_sup*spread(max(S(:,1:min(10,size(S,2))),[],2),f_sd)';

% T stores the actual decaying threshold, for debugging
T = 0*S;

for i = 1:size(S,2)-1
  if any( S(:,i) > sthresh )  % efficiency: about 85% of frames stop here

    s_this = S(:,i);
    sdiff = max(0,(s_this - sthresh))';
  % find local maxima
  %sdiff = locmax(sdiff);
  % avoid function call this deep in the loop
%  sdiff(find(sdiff(1:end-1)<sdiff(2:end))) = 0;
%  sdiff(1+find(sdiff(2:end)<sdiff(1:end-1))) = 0;
%  % (make sure last bin is never a local max since its index
%  % doesn't fit in 8 bits)
%  sdiff(end) = 0;  % i.e. bin 257 from the sgram
%  % take up to 5 largest
%  [vv,xx] = sort(sdiff, 'descend');
%  % (keep only nonzero)
%  xx = xx(vv>0);

    %[pks,locs] = findpeaks(sdiff);
    dsdiff = diff([0,sdiff,0]);
    locs = find((dsdiff(1:end-1) > 0) & (dsdiff(2:end)<=0));
    pks = sdiff(locs);
    [vv,xx] = sort(pks,'descend');
    % store those peaks and update the decay envelope
    nmaxthistime = 0;
    for j = 1:length(xx)
      %p = xx(j);
      p = locs(xx(j));
      if nmaxthistime < maxpksperframe
        % Check to see if this peak is under our updated threshold
        if s_this(p) > sthresh(p)
          nmaxthistime = nmaxthistime + 1;
          nmaxes = nmaxes + 1;
          maxes(2,nmaxes) = p;
          maxes(1,nmaxes) = i;
          maxes(3,nmaxes) = s_this(p);
          eww = exp(-0.5*(([1:length(sthresh)]'- p)/f_sd).^2);
          sthresh = max(sthresh, s_this(p)*s_sup*eww);
        end
      end
    end
  end
  T(:,i) = sthresh;
  sthresh = a_dec*sthresh;
end

% Backwards pruning of maxes
maxes2 = [];
nmaxes2 = 0;
whichmax = nmaxes;
sthresh = s_sup*spread(S(:,end),f_sd)';
for i = (size(S,2)-1):-1:1
  while whichmax > 0 && maxes(1,whichmax) == i
    p = maxes(2,whichmax);
    v = maxes(3,whichmax);
    if  v >= sthresh(p)
      % keep this one
      nmaxes2 = nmaxes2 + 1;
      maxes2(:,nmaxes2) = [i;p];
      eww = exp(-0.5*(([1:length(sthresh)]'- p)/f_sd).^2);
      sthresh = max(sthresh, v*s_sup*eww);
    end
    whichmax = whichmax - 1;
  end
  sthresh = a_dec*sthresh;
end

maxes2 = fliplr(maxes2);

%% Pack the maxes into nearby pairs = landmarks
  
% Limit the number of pairs that we'll accept from each peak
maxpairsperpeak=3;

% Landmark is <starttime F1 endtime F2>
L = zeros(nmaxes2*maxpairsperpeak,4);

nlmarks = 0;

for i =1:nmaxes2
  startt = maxes2(1,i);
  F1 = maxes2(2,i);
  maxt = startt + targetdt*OVERSAMP;
  minf = F1 - targetdf;
  maxf = F1 + targetdf;
  % This line takes longer than the specgram for 30 min queries
  % Could improve by limiting portion of maxes2 which is examined
  matchmaxs = find((maxes2(1,:)>startt)&(maxes2(1,:)<maxt)&(maxes2(2,:)>minf)&(maxes2(2,:)<maxf));
  if length(matchmaxs) > maxpairsperpeak
    % limit the number of pairs we make; take first ones, as they
    % will be closest in time
    matchmaxs = matchmaxs(1:maxpairsperpeak);
  end
  for match = matchmaxs
    nlmarks = nlmarks+1;
    L(nlmarks,1) = round(startt/OVERSAMP);
    L(nlmarks,2) = F1;
    L(nlmarks,3) = maxes2(2,match);  % frequency row
    L(nlmarks,4) = round( (maxes2(1,match)-startt)/OVERSAMP);  % time column difference
  end
end

L = L(1:nlmarks,:);

if verbose
  disp(['find_landmarks: ',num2str(length(D)/targetSR),' secs, ',...
      num2str(size(S,2)),' cols, ', ...
      num2str(nmaxes),' maxes, ', ...
      num2str(nmaxes2),' bwd-pruned maxes, ', ...
      num2str(nlmarks),' lmarks']);
end
  
% for debug return, return the pruned set of maxes
maxes = maxes2;


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function Y = locmax(X)
%  Y contains only the points in (vector) X which are local maxima

% Make X a row
X = X(:)';
nbr = [X,X(end)] >= [X(1),X];
% >= makes sure final bin is always zero
Y = X .* nbr(1:end-1) .* (1-nbr(2:end));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function Y = spread(X,E)
%  Each point (maxima) in X is "spread" (convolved) with the
%  profile E; Y is the pointwise max of all of these.
%  If E is a scalar, it's the SD of a gaussian used as the
%  spreading function (default 4).
% 2009-03-15 Dan Ellis dpwe@ee.columbia.edu

if nargin < 2; E = 4; end
  
if length(E) == 1
  W = 4*E;
  E = exp(-0.5*[(-W:W)/E].^2);
end

X = locmax(X);
Y = 0*X;
lenx = length(X);
maxi = length(X) + length(E);
spos = 1+round((length(E)-1)/2);
for i = find(X>0)
  EE = [zeros(1,i),E];
  EE(maxi) = 0;
  EE = EE(spos+(1:lenx));
  Y = max(Y,X(i)*EE);
end


