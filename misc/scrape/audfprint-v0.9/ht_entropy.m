function H = ht_entropy()
% H = ht_entropy()
%    Return the entropy (average number of bits per hash in data) 
%    based on the current hash table.
% 2011-06-14 Dan Ellis dpwe@ee.columbia.edu

global HashTableCounts

nh = sum(HashTableCounts);
ph = HashTableCounts/nh;
H = -ph*log(max(1/nh,ph'))/log(2);

disp(['#Hashes: ', num2str(nh), ...
      ' %oc: ', sprintf('%.1f',100*mean(HashTableCounts>0)), ...
      ' Hent: ', sprintf('%.1f',H),' bits']);


                       
