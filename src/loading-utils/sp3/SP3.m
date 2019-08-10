classdef SP3
    properties
        fileList (1,1) fileList
        header (1,:) SP3header
        gnss
        interval (1,1) double = 900
        t (:,9) double
        sat
        pos
        clockData
        satTimeFlags
    end
    
    methods
        function obj = SP3(cellFilelist,interval,filtergnss)
            if nargin > 1
                assert(rem(interval,1)==0,'Input resampling interval has to be integer!');
                if nargin == 2
                    obj.interval = interval;
                    filtergnss = 'GRECJIL';
                elseif  nargin == 3
                    obj.interval = interval;
                end
            end
            obj.fileList = fileList(cellFilelist,{'SP3','sp3','eph','EPH'});
            temp = struct('pos',[],'t',[],'sat',[],'clockData',[],'satTimeFlags',[]);
            for i = 1:numel(obj.fileList.fileNames)
                f = obj.fileList.fileNames{i};
                obj.header(i) = SP3header(f);
                if rem(obj.interval,obj.header(i).interval)~=0
                    error('Input file "%s" cannot be resampled: mismatch between SP3 interval (%ds) and user interval (%ds)!',...
                        obj.header(i).filename,obj.header(i).interval,obj.interval); 
                end
                [temp(i).pos,temp(i).t,temp(i).sat,temp(i).clockData,temp(i).satTimeFlags] = SP3.loadContent(f,obj.interval/obj.header(i).interval,filtergnss);
                g = intersect(strjoin(fieldnames(obj.header(i).sat),''),filtergnss);
                for j = 1:numel(g)
                    s = g(j);
                    if ~isequal(temp(i).sat.(s),obj.header(i).sat.(s))
                        warning('Inconsistency between HEADER and BODY satellite list for %s system in "%s" file!',s,obj.header(i).filename) 
                    end
                end
            end
            if numel(obj.fileList.fileNames) == 1
                obj.pos = temp.pos;
                obj.t = temp.t;
                obj.sat = temp.sat;
                obj.clockData = temp.clockData;
                obj.satTimeFlags = temp.satTimeFlags;
            else
                [obj.pos, obj.t, obj.sat, obj.clockData, obj.satTimeFlags] = SP3.mergeContent(temp);
                obj.gnss = strjoin(fieldnames(obj.sat),'');
            end
        end
        function saveToMAT(obj,outMatFullFileName)
            if nargin == 1
                outMatFileName = 'preciseEph.mat';
                outMatFullFileName = fullfile(obj.fileList.path{1}, outMatFileName);
            end
            outMatFileName = strsplit(outMatFullFileName,{'/','\'});
            outMatFileName = outMatFileName{end};
            fprintf('Saving loaded EPH to to "%s" ',outMatFileName);
            save(outMatFullFileName,'obj');
            fprintf(' [done]\n')
        end
        function [x,y,z] = interpolatePosition(obj,satsys,prn,mtime)
            prnIdx = find(obj.sat.(satsys) == prn);
            if ~isempty(prnIdx)
                for i = 1:numel(mtime)
                    midIdx = find(obj.t(:,9) - mtime(i) >= 0,1,'first');
                    idxStart = midIdx - 5;
                    idxEnd = midIdx + 4;
                    x = lagrange(obj.t(idxStart:idxEnd,9),obj.pos.(satsys){prnIdx}(idxStart:idxEnd,1),mtime(i));
                    y = lagrange(obj.t(idxStart:idxEnd,9),obj.pos.(satsys){prnIdx}(idxStart:idxEnd,2),mtime(i)); 
                    z = lagrange(obj.t(idxStart:idxEnd,9),obj.pos.(satsys){prnIdx}(idxStart:idxEnd,3),mtime(i)); 
                end
            else
                error('Satellite %s not available in ephemeris!',prn);
            end
        end
    end
    methods (Static)
        function [pos, t, sat, clockData, satTimeFlags] = loadContent(filename,downsampleFactor,filtergnss)
            if nargin == 1
                downsampleFactor = 1; % Load each epochs by default
                filtergnss = 'GRECJIL'; % Default no filtering at all
            end
            if nargin == 2
                filtergnss = 'GRECJIL';
            end
            validateattributes(filename,{'char'},{'size',[1,NaN]},1);
            validateattributes(downsampleFactor,{'double'},{'size',[1,1],'>=',1},2);
            validateattributes(filtergnss,{'char'},{'size',[1,NaN]},3);
            assert(rem(downsampleFactor,1)==0,'Input value "downsampleFactor" has to be integer!');
            assert(nnz(ismember(filtergnss,'GRECJIL'))==numel(filtergnss),'Input value "filtergnss" must me one or more chars of "GRECJIL"!')

            [~,f,fe] = fileparts(filename);
            fprintf('Loading content of SP3 file: %s ',[f,fe]);
            finp = fopen(filename,'r');
            raw = textscan(finp,'%s','Delimiter','\n','Whitespace', '');
            raw = raw{1};
            fclose(finp);
            
            % Get epochs
            totalEpochs = find(cellfun(@(x) strcmp(x(1),'*'),raw));
            selEpochs = totalEpochs(1:downsampleFactor:end);
            contentStartIdx = selEpochs(1);
            ymdhms = cell2mat(cellfun(@(x) sscanf(x(2:end),'%f')', raw(selEpochs),'UniformOutput',false));
            [gpsweek, tow, ~, ~] = greg2gps(ymdhms);
            t = [ymdhms, gpsweek, tow, datenum(ymdhms)];

            % Allocate structure fields for different systems
            satsys = cellfun(@(x) x(2),raw(contentStartIdx:end-1))';
            gnss = strtrim(unique(satsys));
            gnss = intersect(gnss,filtergnss);
            for i = 1:numel(gnss)
                selgnss = cellfun(@(x) strcmp(x(2),gnss(i)),raw);
                sat.(gnss(i)) = unique(cellfun(@(x) str2double(x(3:4)),raw(selgnss))');
                pos.(gnss(i)) = cell(1,numel(sat.(gnss(i))));
                pos.(gnss(i))(:) = {zeros(size(t,1),3)};
                clockData.(gnss(i)) = cell(1,numel(sat.(gnss(i))));
                clockData.(gnss(i))(:) = {NaN(size(t,1),1)};
                satTimeFlags.(gnss(i)) = false(size(t,1),numel(sat.(gnss(i))));
            end
            
            if downsampleFactor ~= 1
                fprintf('\nDownsampling content of "%s" to %d seconds ',[f,fe],mean(diff(tow)))
            end
            % Looping through the file
            idxEpoch = 0;
            skipEpoch = 0;
            for i = 1:numel(totalEpochs)
                if skipEpoch == 0
                	idxEpoch = idxEpoch + 1;
                    idxLine = totalEpochs(i)+1;
                    while 1
                        line = raw{idxLine};
                        idxLine = idxLine+1;
                        if strcmp(line(1),'P')
                            if ismember(line(2),gnss)
                                prn = sscanf(line(3:4),'%f');
                                xyzc = sscanf(line(5:60),'%f')';
                                idxSat = find(sat.(line(2)) == prn);
                                pos.(line(2)){idxSat}(idxEpoch,:) = xyzc(1:3)*1e3;
                                if round(xyzc(4)) ~= 1e6
                                    clockData.(line(2)){idxSat}(idxEpoch,:) = xyzc(4);
                                end
                                satTimeFlags.(line(2))(idxEpoch,idxSat) = true;
                            end
                        else
                            skipEpoch = downsampleFactor - 1;
                            break
                        end
                    end
                else
                    skipEpoch = skipEpoch - 1;
                end
            end
            fprintf('[done]\n');
        end
        function [pos, t, sat, clockData, satTimeFlags] = mergeContent(contentStruct)
            diffFields = setdiff(fieldnames(contentStruct),{'pos','t','sat','clockData','satTimeFlags'}');
            if ~isempty(diffFields)
                error('Input content structure is missing fields: %s',strjoin(diffFields,','));
            else
                gnssAll = '';
                for i = 1:numel(contentStruct)
                    gnssAll = [gnssAll, strjoin(fieldnames(contentStruct(i).sat)','')];
                end
                gnssAll = unique(gnssAll);
                tAll = [];
                for i = 1:numel(contentStruct)
                    tAll = [tAll; contentStruct(i).t];
                end
                [tAllunique, tAllidx] = unique(tAll(:,9));
                if numel(tAllunique) ~= numel(tAll(:,9))
                    idxMoreTimes = 1:numel(tAll(:,9));
                    idxMoreTimes(tAllidx) = [];
                    for i = 1:numel(idxMoreTimes)
                        d = sprintf('%04d/%02d/%02d %02d:%02d:%02d',tAll(idxMoreTimes(i),1:6));
                        warning('SP3 merging: time conflict for t: %s, position from first input file will be used!',d);
                    end
                end
                t = tAll(tAllidx,:);
                
                for i = 1:numel(gnssAll)
                    sats = [];
                    s = gnssAll(i);
                    for j = 1:numel(contentStruct)
                        sats = [sats, contentStruct(j).sat.(s)];
                    end
                    sat.(s) = unique(sats);
                    pos.(s) = cell(1,numel(sat.(s)));
                    pos.(s)(:) = {zeros(size(tAll,1),3)};
                    clockData.(s) = cell(1,numel(sat.(s)));
                    clockData.(s)(:) = {zeros(size(tAll,1),1)};
                    satTimeFlags.(s) = zeros(size(tAll,1),numel(sat.(s)));
                    for j = 1:numel(sat.(s))
                        satNoMerged = sat.(s)(j);
                        nStart = 1;
                        for k = 1:numel(contentStruct)
                            idxContentStruct = find(contentStruct(k).sat.(s) == satNoMerged);
                            nEnd = nStart+size(contentStruct(k).t,1)-1;
                            if ~isempty(idxContentStruct)
                                pos.(s){j}(nStart:nEnd,:) = contentStruct(k).pos.(s){idxContentStruct};
                                clockData.(s){j}(nStart:nEnd,:) = contentStruct(k).clockData.(s){idxContentStruct};
                                satTimeFlags.(s)(nStart:nEnd,j) = contentStruct(k).satTimeFlags.(s)(:,idxContentStruct);
                            end
                            if k < numel(contentStruct)
                                nStart = nEnd+1;
                            end
                        end
                    end
                    for j = 1:numel(sat.(s))
                        pos.(s){j} = pos.(s){j}(tAllidx,:);
                        clockData.(s){j} = clockData.(s){j}(tAllidx,:);
                    end
                    satTimeFlags.(s) = satTimeFlags.(s)(tAllidx,:);
                end
            end
        end
        function obj = loadFromMAT(filepath)
            xobj = load(filepath);
            propAre1 = fieldnames(xobj.obj);
            propAre2 = fieldnames(xobj.obj.header);
            propAre3 = fieldnames(xobj.obj.fileList);
            propShould1 = properties('SP3');
            propShould2 = properties('SP3header');
            propShould3 = properties('fileList');
            
            if isempty(setdiff(propAre1,propShould1)) && isempty(setdiff(propAre2,propShould2)) && isempty(setdiff(propAre3,propShould3))
                obj = xobj.obj;
                fprintf('SP3 file loaded from file "%s"\n',filepath)
            else
                error('Input MAT file has not complete SP3 format structure!');
            end

            % Update filename and path to input MAT file
            obj.fileList = fileList({filepath});
        end
	end
end