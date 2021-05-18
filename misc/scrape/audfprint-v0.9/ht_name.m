function N = ht_name(X)
% N = ht_name(X)
%    Convert an ID code (as returned by ht_match) to an actual
%    string (as passed to ht_store).
% 2011-12-01 Dan Ellis dpwe@ee.columbia.edu

global HashTableNames

N = HashTableNames{X};
