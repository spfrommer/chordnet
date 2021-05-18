function [H,THOP] = ht_retrieve(A)
% [H,THOP] = ht_retrieve(A)
%   Retrieve all the entries stored in the hash table associated
%   with name A.  (or set A to the numeric ID).
%   Returns H as 2 column <start_time_index> <hash> rows, just like
%   they were passed to ht_store.
%
% 2013-04-24 Dan Ellis dpwe@ee.columbia.edu

global HashTable HashTableCounts HashTableNames HT_params

[nhtcols,nhtrows] = size(HashTable); % rows/cols named oddly

% (just used to inform match_query_hashes)
THOP = HT_params.hoptime;

%TIMESIZE = 16384;
TIMESIZE = HT_params.timesize;

if ischar(A)
  ID = strmatch(A, HashTableNames, 'exact');
else
  % Numeric - just the ID itself
  ID = A;
end

% Div on int types implicitly rounds, so precompensate
matches = find(((HashTable(:)-TIMESIZE/2)/TIMESIZE) == ID);

H = [rem(HashTable(matches), TIMESIZE), floor((matches-1)/nhtcols)];

[vv,ix] = sort(H(:,1));
H = H(ix,:);

% except ... the jenkinshash applied to the actual hash value can't
% be undone....