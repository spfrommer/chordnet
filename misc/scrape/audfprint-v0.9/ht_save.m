function ht_save(DBASE,HOPTIME,VERSION)
% ht_save(DBASE,HOPTIME,VERSION)
%   Save the fingerprint database to the file DBASE.
%   Optionally update HOPTIME with its true value.
%   Optionally set a VERSION value.
% 2011-12-01 Dan Ellis dpwe@ee.columbia.edu

global HashTable HashTableCounts HashTableNames HashTableLengths HT_params

if nargin > 1;   
  if HOPTIME ~= 0
    HT_params.hoptime = HOPTIME; 
  end
end
if nargin > 2;   HT_params.version = VERSION; end

% Check that the HashTableCounts is consistent
% (will fix & set dirty flag if not)
% (not sure how it gets broken, but it has happened)
ht_repair();

if HT_params.dirty == 0
%  disp(['ht_save: NOT saving to ', DBASE,', ht is clean']);
else
  % it won't be dirty now, we will have just saved it
  HT_params.dirty = 0;
  save(DBASE, 'HashTable', 'HashTableCounts', 'HashTableNames', ...
       'HashTableLengths', 'HT_params');
  % Figure the number of nonzero names in HashTableNames
  namelens = cellfun(@length, HashTableNames);
  disp(['Hash table saved to ',DBASE,' (', ...
        num2str(sum(namelens>0)), ' tracks, ', ...
        num2str(sum(HashTableCounts)), ' hashes)']);
 end
