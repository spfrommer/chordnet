function dirty = ht_repair()
% dirty = ht_repair()
%   Update the HashTableCounts to be consistent with the hash
%   table.  Somehow it can get out of sync, which "track 0" being
%   returned.  Returns 1 if any repairs actually done.
% 2012-12-22 Dan Ellis dpwe@ee.columbia.edu

%>> ht_load('/base/db/dbase.mat');
%Hash table read from /base/db/dbase.mat (21236 tracks, 38345869 hashes)
global HashTable HashTableCounts HashTableLengths HT_params
% How many nonzero entries in each row of hash table?
% (as index of first zero element, if any)
[mv,mvx] = min([HashTable;zeros(1,size(HashTable,2))],[],1);
HTCtAct = mvx - 1;
HTCtClp = min(size(HashTable,1),HashTableCounts);

er = find(HTCtClp ~= HTCtAct); % buckets with too few entries
if length(er > 0)
  disp(['**ht_repair: ', num2str(length(er)),...
        ' buckets found with too few entries']);
  % Fix them
  HashTableCounts(er) = HTCtAct(er);
  HT_params.dirty = 1;
  %>> ht_save('/base/db/dbase_fixed.mat');
  %Hash table saved to /base/db/dbase_fixed.mat (21236 tracks, 38223362 hashes)
end

% Make sure nojenkins field is set
if isfield(HT_params, 'nojenkins') == 0
  HT_params.nojenkins = 0;
end

% Contruct HashTableLengths if it's not in the file
ht_lengths();

dirty = HT_params.dirty;
