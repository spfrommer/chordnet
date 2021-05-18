function N = ht_remove(A)
% N = ht_remove(A)
%   Remove all hashes associated with identifier A from database.
%   If A is a string, look it up in the HashTableNames structure.
%   If A is numeric, treat it as the track ID.
% N returns the actual number of hashes removed.
%
% 2012-05-14 Dan Ellis dpwe@ee.columbia.edu

% This version uses an in-memory global with one row per hash
% value, and a series of song ID / time ID entries per hash

global HashTable HashTableCounts HashTableNames HT_params

%if exist('HashTable','var') == 0 || length(HashTable) == 0
%   ht_clear
%end

N = 0;

if isstr(A)
  ID = strmatch(A,HashTableNames);
  if length(ID) == 0
    disp(['Warn: ht_remove: track ',A,' not in HashTableNames']);
    return
  end
  ID = ID(1);
else
  ID = A;
end

%TIMESIZE = 16384;
TIMESIZE = uint32(HT_params.timesize);

% IDs for every item in the hash table
% this will (temporarily) double the storage required
IDs = idof_htval(HashTable, TIMESIZE);
remove = find(IDs==ID);
% Free memory
clear('IDs');
removecols = unique(1+floor((remove-1)/size(HashTable,1)));
for i = 1:length(removecols)
  htcol = HashTable(:,removecols(i));
  idcol = idof_htval(htcol, TIMESIZE);
  nremove = length(find(idcol == ID));
  htcol = [htcol(find(idcol ~= ID));zeros(nremove,1)];
  HashTable(:,removecols(i)) = htcol;
  N = N + nremove;
  HashTableCounts(removecols(i)) = ...
      HashTableCounts(removecols(i)) - nremove;
end

% Remove the name too
HashTableNames{ID} = '';

% If trailing entries in table name are empty, back up the counter
ID = length(HashTableNames);
while length(HashTableNames{ID}) == 0,
  ID = ID - 1;
  HashTableNames = HashTableNames(1:ID);
end

% mark as unsaved
HT_params.dirty = 1;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function ID = idof_htval(HTVAL,TIMESIZE)
ID = (HTVAL-(TIMESIZE/2))/TIMESIZE;
