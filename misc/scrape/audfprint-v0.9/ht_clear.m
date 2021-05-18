function ht_clear(nhashes, maxnentries,TIMESIZE,HOPTIME,TARGETSR,NOJENKINS)
% ht_clear(nhashes, maxnentries,TIMESIZE,HOPTIME,TARGETSR,NOJENKINS)
%  Access the persistent store to reset the hash table.
% 2008-12-29 Dan Ellis dpwe@ee.columbia.edu

global HashTable HashTableCounts HashTableNames HashTableLengths HT_params

if nargin < 3
  % How many bits are used for time offset
  TIMESIZE = 16384;
end
if nargin < 4
  % actual time in timebase
  HOPTIME = 256/11025;
end
if nargin < 5
  % sampling rate used in find_landmarks
  TARGETSR = 11025;
end
if nargin < 6
  % do we (not) use jenkinshash?
  NOJENKINS = 0;
end

if ~NOJENKINS
  % Make sure the hash mex is set
  mexfname = 'jenkinshash';
  HAVE_MEX = (exist(mexfname)==3);
  if HAVE_MEX == 0
    try 
      disp(['compiling ',mexfname,'...']);
      mex([mexfname,'.c']);
    end
  end
  HAVE_MEX = (exist(mexfname)==3);
end

%if exist('HashTable','var') == 0
%   HashTable = [];
%end

if nargin < 1
  nhashes = 2^20;
end

% 1M hashes x 32 bit entries x 100 entries = 400MB in core
if nargin < 2
  maxnentries = 100;
end

%disp(['Max entries per hash = ',num2str(maxnentries)]);

% nhashes needs to be a power of 2
assert(nhashes == 2^round(log(nhashes)/log(2)));

HT_params.nhashes = nhashes;
HT_params.maxnentries = maxnentries;
HT_params.timesize = TIMESIZE;

HT_params.hoptime = HOPTIME;
HT_params.targetSR = TARGETSR;

HT_params.nojenkins = NOJENKINS;

%if length(HashTable) == 0
  HashTable = zeros(maxnentries, nhashes, 'uint32');
  HashTableCounts = zeros(1, nhashes);
%end

% Reset the table that maps hash table indices to names
HashTableNames = cell(0);

% Reset the thing that keeps track of how many hashes per track
HashTableLengths = [];

% mark as unsaved
HT_params.dirty = 1;

