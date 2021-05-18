function H = landmark2hash(L)
% H = landmark2hash(L)
%  Convert a set of 4-entry landmarks <t1 f1 f2 dt> 
%  into a set of <time hash> pairs ready to store.
% 2008-12-29 Dan Ellis dpwe@ee.columbia.edu

% Hash value is 20 bits: 8 bits of F1, 6 bits of delta-F, 6 bits of delta-T

F1bits = 8;
DFbits = 6;
DTbits = 6;

H = uint32(L(:,1));
% Make sure F1 is 0..255, not 1..256
F1 = mod(round(L(:,2)-1),2^F1bits);
DF = round(L(:,3)-L(:,2));
if DF < 0
  DF = DF + 2^DFbits;
end
DF = mod(DF,2^DFbits);
DT = mod(abs(round(L(:,4))), 2^DTbits);
H = [H,uint32(F1*(2^(DFbits+DTbits))+DF*(2^DTbits)+DT)];
