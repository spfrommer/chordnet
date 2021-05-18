function H = ht_lengths()
% H = ht_lengths()
%   Rebuild ht_lengths structure, the number of hashes known for
%   each ID.  
%
% 2013-05-27 Dan Ellis dpwe@ee.columbia.edu

global HashTable HashTableCounts HashTableNames HashTableLengths HT_params

if length(HashTableLengths) == 0

  nIDs = length(HashTableNames);
  HashTableLengths = ones(1, nIDs);

  disp('rebuilding HashTableLengths');

  [nhtcols,nhtrows] = size(HashTable); % rows/cols named oddly

  %TIMESIZE = 16384;
  TIMESIZE = HT_params.timesize;

  % Div on int types implicitly rounds, so precompensate
  HIDs = (HashTable(:)-TIMESIZE/2)/TIMESIZE;
  HIDs = HIDs(find(HIDs(:)>0));

  for i = 1:nIDs
    HashTableLengths(i) = sum(HIDs == i);
    if rem(i,100) == 0
      fprintf('%d.. ', i);
    end
  end
  fprintf('\n');
  HT_params.dirty = 1;
  
end

