function L = hash2landmark(H)
% L = hash2landmark(H)
%  Convert a set of <time hash> pairs ready from store 
%  into a set of 4-entry landmarks <t1 f1 f2 dt>.
%  If H is 3 cols, first col (song ID) is discarded.
% 2008-12-29 Dan Ellis dpwe@ee.columbia.edu

% Hash value is 20 bits: 8 bits of F1, 6 bits of F2-F1, 6 bits of delta-T

%H = uint32(L(:,1));
%F1 = rem(round(L(:,2)),2^7);
%F2 = rem(round(L(:,4)),2^7);
%DT = rem(abs(round(L(:,3) - L(:,1))), 2^6);
%H = [H,uint32(F1*(2^13)+F2*(2^6)+DT)];

if size(H,2) == 3
  H = H(:,[2 3]);
end

H = double(H);

F1bits = 8;
DFbits = 6;
DTbits = 6;

H1 = H(:,1);
H2 = H(:,2);
F1 = floor(H2/(2^(DFbits+DTbits)));
H2 = H2 - (2^(DFbits+DTbits))*F1;
F1 = F1 + 1;
DF = floor(H2/(2^DTbits));
% DT is residual after removing unsigned DF
DT = H2 - (2^DTbits)*DF;
% now fix sign on DF
DF = DF-((DF >= (2^(DFbits-1)))*(2^DFbits));
F2 = F1+DF;

L = [H1,F1,F2,DT];
