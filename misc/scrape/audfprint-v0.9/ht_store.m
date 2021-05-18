function N = ht_store(H,A)
% N = ht_store(H,A)
%   Record the set of hashes that are rows of H in persistent
%   database, associated with filename A.
%   Format of H rows are 2 columns:
%   <start_time_index> <hash>
%   time_index is ? 12 bit (i.e. integer out to 16384)
% Hash is a 32 bit int val, is hashed and masked to 20 bits
% N returns the actual number of hashes saved (excluding table overflows).
%
% 2008-12-24 Dan Ellis dpwe@ee.columbia.edu

% This version uses an in-memory global with one row per hash
% value, and a series of song ID / time ID entries per hash

global HashTable HashTableCounts HashTableNames HashTableLengths HT_params

%if exist('HashTable','var') == 0 || length(HashTable) == 0
%   ht_clear
%end

% Fill in next slot in HashTable record
ID = length(HashTableNames) + 1;

maxnentries = size(HashTable,1);
nhashes = size(HashTable,2);

nhash = size(H,1);

% Mask the hash val at 20 bits, hash it up first
% assumes nhashes is a power of 2!
Hvals = ht_hash(H(:,2));

N = 0;

%TIMESIZE = 16384;
TIMESIZE = HT_params.timesize;

if ID > 2^32/TIMESIZE
  error(['Track ID ', num2str(ID), ...
         ' overflow - rebuild with smaller -timesize']);
end

% Otherwise, we're good to store it:
HashTableNames{ID} = A;
HashTableLengths(ID) = nhash;

% Joren Six caching
%entries = zeros(nhash,3);

for i=1:nhash
  toffs = mod(round(H(i,1)), TIMESIZE);
  hash = 1+Hvals(i); % avoid hash == 0
  htcol = HashTable(:,hash);
  nentries =  HashTableCounts(hash) + 1;
  if nentries <= maxnentries
	% put entry in next available slot
	r = nentries;
  else
    % choose a slot at random; will only be stored if it falls into
    % the first maxnentries slots (whereupon it will replace an older 
    % value).  This approach guarantees that all values we try to store
    % under this hash will have an equal chance of being retained.
    r = ceil(nentries*rand(1));
  end
  if r <= maxnentries
    hashval = uint32(ID*TIMESIZE + toffs);
%    disp(num2str(floor(double(hashval)/TIMESIZE)));
    HashTable(r,hash) = hashval;
%    entries(i,:) = [r,hash,hashval];
    N = N+1;
  end
  HashTableCounts(hash) = nentries;
end

% Mark the database as modified
HT_params.dirty = 1;

% Joren Six optimization (for Octave?)
%for i = 1:nhash
%  r = entries(i,1);
%  hash = entries(i,2);
%  hashval = entries(i,3);
%  if r > 0 & hash > 0
%    HashTable(r,hash) = hashval;
%  end
%end
