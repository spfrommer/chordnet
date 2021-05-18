function [H,O,S,Hc] = alignhashes(H1,H2,thop,doplot)
% [H,O,S,Hc] = alignhashes(H1,H2,thop,doplot)
%    Take two sets of hashes, find and plot all the matching hash
%    points, try to fit a linear slope to it.
%    Return matching hashes from H2 in H, and linear-fit slope 
%    parameters s.t. t(T1) = O + S*t(T2).
%    thop is the time resolution of the basic grid.
%    doplot enables display of results (default: 1).
% 2010-10-11 Dan Ellis dpwe@ee.columbia.edu

if nargin < 3;  thop = 353/11025; end  % should be 256/11025 for newfp_ota
if nargin < 4;  doplot = 1; end

if usejava('jvm')==0; doplot = 0; end % no display available in -nojvm

% Go through hashes from H1, finding all matches in H2

% check for filenames not hashes
if ischar(H1)
  [H1,thop] = find_landmarks(H1,0);
end
if ischar(H2)
  [H2,thop] = find_landmarks(H2,0);
end

tsize = 1024;
dts = zeros(tsize,2);
ixs = zeros(tsize,2);
ndt=0; 

% avoid integers
H1 = double(H1);
H2 = double(H2);

% (keep track of max time implied by H1, for sox command later)
maxdur = max(H1(:,1)) * thop + 5.0;  % add 5 sec off the end

% Only consider each unique hash once
[B,I,J] = unique(H1(:,2),'first');

%for i = 1:size(H1,1); 
for i = 1:size(I)
  ix = find(H2(:,2)==H1(I(i),2)); 
  if length(ix) > 0; 
    ndt = ndt+1;
    if ndt > tsize;
      dts = [dts;zeros(tsize,size(dts,2))];
      ixs = [ixs;zeros(tsize,size(ixs,2))];
      tsize = size(dts,1);
    end
%    dts(ndt,:)=[H1(i,1),H2(ix(ceil(length(ix)*rand(1))),1)];
    dts(ndt,:)=thop*[H1(I(i),1),H2(ix(1),1)];
    ixs(ndt,:)=[I(i),ix(1)];
  end
end

dts = dts(1:ndt,:);
ixs = ixs(1:ndt,:);

Hc = H2(ixs(:,2),:);

% Bail if no match
if length(dts) == 0
  disp('No good match found for alignment');
  H = zeros(0,2);
  Hc = zeros(0,2);
  O = 0;
  S = 1;
  return
end


% Find best linear fit to time differences

% Search over time warps, since otherwise may miss it
bestngooddts = 0;
bestgoodDTs = [];
bestwarp = 0;
for warp = -0.02:0.001:0.02
  DTs = dts(:,2) - (1+warp)*dts(:,1);

  % assume good matches are tightly distributed around median - allow
  % +/-100ms (or +/- 10 s from center for 1% time skew)
  vv = sort(DTs);
  medianDT = vv(round(length(vv)/2));

  % modal dt?
  [nn,tt] = hist(vv,[-300:0.05:300]);

  % delete extreme bins
  nn(1) = 0; nn(end) = 0;
  [vv,xx] = sort(nn, 'descend');
  medianDT = tt(xx(1));
  
  %  plot(tt,nn, [medianDT, medianDT], [0 max(nn)], '-r');
  
%  tthr = 512/11025;
  tthr = 0.064;
  goodDTs = find( abs(DTs-medianDT) < tthr );
  disp([]);
  
  ngooddts = length(goodDTs);
%  disp(['warp=',num2str(warp),...
%        ' modal time skew=',num2str(medianDT),' s',...
%        ' ngooddts=',num2str(ngooddts)]);
  if ngooddts > bestngooddts
    bestngooddts = ngooddts;
    bestgoodDTs = goodDTs;
    bestwarp = warp;
  end
end

goodDTs = bestgoodDTs;

DTs = dts(:,2) - dts(:,1);
  
disp([num2str(length(H1)),';',num2str(length(H2)),' hashes, ', ...
      num2str(ndt),' in common, ', num2str(length(goodDTs)), ...
      ' within ',num2str(tthr),' s of median for warp ',num2str(bestwarp)]);

% Least-squares fit to those points
%A = [dts(goodDTs,1),ones(length(goodDTs),1)] \ DTs(goodDTs);
A = [dts(goodDTs,1),ones(length(goodDTs),1)] \ (dts(goodDTs,2)-dts(goodDTs,1));
O = A(2);
S = 1+A(1);

if doplot
  plot(dts(1:ndt,1), dts(1:ndt,2)-dts(1:ndt,1),'.b', ...
       dts(goodDTs,1), dts(goodDTs,1)*(S-1) + O, '-c', ...
       dts(goodDTs,1), dts(goodDTs,2)-dts(goodDTs,1), '.r');
  xlabel('time in T1')
  ylabel('time diff T2 - T1');
end

O = O/S;
S = S;

disp(sprintf('Best match for time T sec in tk 1 (ref) is %+.3f+(1%+.6f)*T in tk 2 (qry)', ...
             O,S-1));
% from skewview
targ = '<query.wav>';
alignout = '<alignout.wav>';
if O < 0
  cmd = ['sox ', targ, ' ', alignout, ' speed ', sprintf('%.6f', S), ...
         ' delay ', num2str(-O), ' ', num2str(-O), ...
         ' trim 0 ', num2str(maxdur)];
else
  cmd = ['sox ', targ, ' ', alignout, ' speed ', sprintf('%.6f', S), ...
         ' trim ', num2str(O), ' ', num2str(maxdur)];
end
disp(cmd);

H = H2(ixs(goodDTs,2),:);
