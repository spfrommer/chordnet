function R = ht_get_hits(H)
% R = ht_get_hits(H)
%    Return values from song hash table for particular hashes
%    Each element of H is a <hash_value>
%    Each row of R is a hit in format:
%    <song id> <time_difference> <hash> <start_time_index>
%    If H is a 2 column matrix, the first element is taken as a
%    time base which is subtracted from the start time index for
%    the retrieved hashes to obtain the time_difference, else
%    time_difference is equal to start_time_index.
% 2008-12-29 Dan Ellis dpwe@ee.columbia.edu

global HashTable HashTableCounts HT_Hsize HT_Rsize HT_params

if size(H,2)==1
  H = [zeros(length(H),1),H(:)];
end

maxnentries = size(HashTable,1);
nhashes = size(HashTable,2);

%TIMESIZE=16384;
TIMESIZE = HT_params.timesize;

% Mask the hash val at 20 bits, hash it up first
Hvals = ht_hash(H(:,2));

Rsize = 16000;  % preallocate
R = zeros(Rsize,4);
Rmax = 0;

for i = 1:length(Hvals)
  hash = 1+Hvals(i);
  htime = double(H(i,1));
  nentries = min(maxnentries,HashTableCounts(hash));
  htcol = double(HashTable(1:nentries,hash));
  songs = floor(htcol/TIMESIZE);
  times = round(htcol-songs*TIMESIZE);
  if Rmax+nentries > Rsize
    R = [R;zeros(Rsize,4)];
    Rsize = size(R,1);
  end
  dtimes = times-htime;
%  R(Rmax+[1:nentries],:) = [songs, dtimes, repmat(double(H(i,2)),nentries,1)];
  % Much faster to avoid the repmat like this:
  R(Rmax+[1:nentries],[1 2]) = [songs, dtimes];
  R(Rmax+[1:nentries],3) = double(H(i,2));
  % include actual hash time as 4th col (new) 
  R(Rmax+[1:nentries],4) = times;
  Rmax = Rmax + nentries;
end

R = R(1:Rmax,:);

% Keep track of selectivity
HT_Hsize = HT_Hsize + size(H,1);
HT_Rsize = HT_Rsize + size(R,1);
