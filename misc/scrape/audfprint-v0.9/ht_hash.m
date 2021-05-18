function H = ht_hash(G)
% H = ht_hash(G)
%   Common function to apply the hashing of original values
%   G is a vector of integer values, H returns as uint64's, with
%   only bottom 32 bits nonzero, hashed to be nicely distributed.
%   If global HT_params.nojenkins is set, it will be a no-op (just
%   mask the bottom 32 bits).
% 2013-04-24

global HashTable HT_params

nhashes = size(HashTable,2);

% Mask the hash val at 20 bits, hash it up first
if HT_params.nojenkins == 0
  H = jenkinshash(uint64(G));
else
  H = uint32(G);
end
H = bitand(H, uint32(nhashes-1));
