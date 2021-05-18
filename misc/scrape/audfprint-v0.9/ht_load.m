function [inver,HOPTIME,TARGETSR] = ht_load(DBASE, VERSION)
% [inver,HOPTIME,TARGETSR] = ht_load(DBASE, VERSION)
%   Load the fingerprint database from the file DBASE.
%   Check that VERSION matches; if there is no version, set it to
%   that.  Returns version of file read, and time grid.
%   Will attempt to rebuild
%   HashTableLengths (numbers of hashes per reference track) on load.
% 2011-12-01 Dan Ellis dpwe@ee.columbia.edu

if nargin < 2;  VERSION = 0; end

global HashTable HashTableCounts HashTableNames HashTableLengths HT_params
HashTable = [];
HashTableCounts = [];
HashTableNames = cell(0);
HashTableLengths = [];
HT_params = [];

load(DBASE);

% assume it's clean on load, ensure it has a dirty field
HT_params.dirty = 0;

inver = 0;
if isfield(HT_params, 'version')
  inver = HT_params.version;
end

if nargin > 1
  % VERSION specified
  if inver ~= 0 && inver ~= VERSION
    disp(['**Warning: version skew: dbase ',DBASE, ...
          ' is ver ', num2str(inver), ...
          ' but code expects ver ', num2str(VERSION)]);
  end
  % Update it to this version regardless
  HT_params.version = VERSION;
end

% Make sure everything is good
ht_repair();

if isfield(HT_params, 'hoptime')
  HOPTIME = HT_params.hoptime;
else
  HOPTIME = 0.02322;
  HT_params.hoptime = HOPTIME;
end

if isfield(HT_params, 'targetSR')
  TARGETSR = HT_params.targetSR;
else
  TARGETSR = 11025;
  HT_params.targetsr = TARGETSR;
end

% Figure the number of nonzero names in HashTableNames
lens = cellfun(@length, HashTableNames);

disp(['Hash table read from ',DBASE,' (', ...
      num2str(sum(lens>0)), ' tracks, ', ...
      num2str(sum(HashTableCounts)), ' hashes)']);

