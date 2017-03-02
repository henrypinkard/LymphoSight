function [] = createSurfaces(surfName,...
    channelIndex, smoothFilter, localContrast, backgroundSub, seedDiam, quality, minNumVoxels)
%CREATESURFACES
% Open a Imaricumpiler "Positions as time" file in Imaris
% this function will prompt user to open  a Micro-Magellan dataset
% to read calibrtion and posiotion metadata
% channelIndex is 0 based, but shows up in Imaris as 1 based
%creates and saves surfaces and statistics, reads image data and masks


%GFP DCs on high res Gen3
%     channelIndex = 2;
%     smoothFilter = 1.5;
%     localContrast = 25;
%     backgroundSub = 2.5;
%     seedDiam = 21;
%   quality = 1
%number of voxels = 150

%CMTMR/e670 T cells on high res Gen3
%     channelIndex = 4/5;
%     smoothFilter = 1.5;
%     localContrast = 20;
%     backgroundSub = 2;
%     seedDiam = 15;
%   quality = 0.5
%number of voxels = 120

%non rank filtered
%3x3x3 median filter
%e670 ltmphocytes on lo res gen3
%     channelIndex = 5;
%     smoothFilter = 1.5;
%     localContrast = 20;
%     backgroundSub = 1.8;
%     seedDiam = 15;
%   quality = 0.1
%number of voxels = 100

%Parameters that can be tuned to optimize performance
batchSize = 100;
framesPerLoop = 10; %number of frames for which surfaces are created with each loop
distanceFromEdge = 4; %remove data points within _ um of edges of tiles

%connect to imaris?
javaaddpath('./ImarisLib.jar');
imarisIndex = 0;
vImarisLib = ImarisLib;
imaris = vImarisLib.GetApplication(imarisIndex);
if (isempty(imaris))
    msgbox('Wrong imaris index');
    return;
end

%select magellan dataset for reading of metadata, etc
magellanDir = '/Users/henrypinkard/Desktop/2017-1-16_Lymphocyte_iLN_calibration/C_600Rad_70MFP_25_BP_MT_600Rad_30MFP_25BP(MT on this time)_1';
% magellanDir = uigetdir('','select Magellan dataset');
% if (magellanDir == 0)
%     return; %canceled
% end
javaaddpath('./dataprocessing/xt/Magellan.jar');
mmData = org.micromanager.plugins.magellan.acq.MultiResMultipageTiffStorage(magellanDir);

summaryMD = JSON.parse(char(mmData.getSummaryMetadata.toString));
posList = mmData.getSummaryMetadata.getJSONArray('InitialPositionList');
imageWidth = summaryMD.Width;
imageHeight = summaryMD.Height;
xPixelOverlap = summaryMD.GridPixelOverlapX;
yPixelOverlap  = summaryMD.GridPixelOverlapY;
pixelSizeXY = summaryMD.PixelSize_um;
pixelSizeZ = summaryMD.z_step_um;
numTimePoints = mmData.getNumFrames;

% Create matlab file to save surface data in
filename = imaris.GetCurrentFileName;
imageProcessing = imaris.GetImageProcessing;
ds = imaris.GetDataSet;
fovSize = [ds.GetExtendMaxX ds.GetExtendMaxY];

%generate saving name
imsFileFullPath = strsplit(char(filename),'.');
imsFilePathAndName = imsFileFullPath{1};
%save in same directory as data
saveName = strcat(imsFilePathAndName,'_',char(surfName),'.mat');
%delete exisiting file with same name
if (exist(saveName,'file') == 2)
    if (strcmp(questdlg('Delete exisiting file'),'Yes'))
        delete(saveName);
    end
end
saveFile = matfile(saveName,'Writable',true);
saveFile.summaryMD = summaryMD;
if ~any(strcmp('vertices',who(saveFile)))
    %initialize fields
    saveFile.stitchedXYZPositions = [];
    saveFile.excitations = [];
    saveFile.masks = {};
    saveFile.imageData = {};
    saveFile.imarisIndices = {};
    startIndex = 0;
    saveFile.vertices = single([]);
    saveFile.triangles = int32([]);
    saveFile.normals = single([]);
    saveFile.timeIndex = int32([]);
    saveFile.numTriangles = int32([]);
    saveFile.numVertices = int32([]);
    saveFile.name = surfName;
    saveFile.surfInterpPoints = {};
else
    startIndex = saveFile.lastWrittenFrameIndex + 1;
end


%Incrementally segment surfaces, get and save their info, and delete
maxFrameIndex = numTimePoints*posList.length-1;
for startFrame = startIndex:framesPerLoop:maxFrameIndex
    tic
    fprintf('Calculating surfaces on frame %i-%i of %i\n',startFrame, startFrame + framesPerLoop, maxFrameIndex);
    % time index is 0 indexed and inclusive, but shows up in imaris as 1
    % indexed
    roi = [0,0,0,startFrame,ds.GetSizeX,ds.GetSizeY,ds.GetSizeZ,min(startFrame + framesPerLoop-1,maxFrameIndex)];
    
    surface = imageProcessing.DetectSurfacesRegionGrowing(ds, roi,channelIndex,smoothFilter,localContrast,false,backgroundSub,...
        seedDiam,true, sprintf('"Quality" above %1.3f',quality),sprintf('"Number of Voxels" above %i',minNumVoxels));
    %only process if there are actually surfaces
    if surface.GetNumberOfSurfaces <= 0
        surface.RemoveAllSurfaces;
        continue;
    end
    
    %get stats
    stats = xtgetstats(imaris, surface, 'ID', 'ReturnUnits', 1);
    %modify stats to reflect stitching
    stats = modify_stats_for_stitched_view(stats);
    
    % iterate through batches of segmeneted surfaces (so as to not overflow
    % memory),
    for i = 0:ceil((surface.GetNumberOfSurfaces)/batchSize ) - 1
        startIndex = batchSize*i;
        endIndex = min(surface.GetNumberOfSurfaces-1, batchSize*(i+1) - 1);
        fprintf('%d to %d of %d\n',startIndex+1, endIndex +1, surface.GetNumberOfSurfaces)
        surfList = surface.GetSurfacesList(startIndex:endIndex);
        %stitch surfaces
        [vertices, tIndices] = modify_surfaces_for_stitched_view(surfList.mVertices, surfList.mTimeIndexPerSurface, surfList.mNumberOfVerticesPerSurface,...
            posList, imageWidth, imageHeight, xPixelOverlap, yPixelOverlap, pixelSizeXY, numTimePoints);
        
        maskTemp = cell(endIndex-startIndex+1,1);
        imgTemp = cell(endIndex-startIndex+1,1);
        excitations = zeros(endIndex-startIndex+1,2);
        %iterate through each surface to get its mask and image data
        for index = startIndex:endIndex
            %get axis aligned bounding box
            boundingBoxSize = [stats(find(strcmp({stats.Name},'BoundingBoxAA Length X'))).Values(index + 1),...
                stats(find(strcmp({stats.Name},'BoundingBoxAA Length Y'))).Values(index + 1),...
                stats(find(strcmp({stats.Name},'BoundingBoxAA Length Z'))).Values(index + 1)];
            positionUnstitched = surface.GetCenterOfMass(index);
            positionStitched = [stats(find(strcmp({stats.Name},'Stitched Position X'))).Values(index + 1),...
                stats(find(strcmp({stats.Name},'Stitched Position Y'))).Values(index + 1),...
                stats(find(strcmp({stats.Name},'Stitched Position Z'))).Values(index + 1)];
            
            
            %Mask is in unstitched coordinates, image data is in stitched coordinates
            topLeftUnstitched = positionUnstitched -  boundingBoxSize / 2;
            bottomRightUnstitched = positionUnstitched + boundingBoxSize / 2;
            topLeftStitched = positionStitched -  boundingBoxSize / 2;
            pixelResolution = int32(ceil((bottomRightUnstitched - topLeftUnstitched) ./ [pixelSizeXY pixelSizeXY pixelSizeZ]));
            topLeftPixStitched = int32(floor([topLeftStitched(1:2) ./ pixelSizeXY topLeftStitched(3) ./ pixelSizeZ]));
            mask = surface.GetSingleMask(index, topLeftUnstitched(1), topLeftUnstitched(2), topLeftUnstitched(3), bottomRightUnstitched(1), bottomRightUnstitched(2),...
                bottomRightUnstitched(3), pixelResolution(1), pixelResolution(2), pixelResolution(3));
            byteMask = uint8(squeeze(mask.GetDataBytes));
            
            timeIndex = tIndices(index+1 - startIndex);
            
            [imgData, md] = readRawMagellan( mmData, byteMask, topLeftPixStitched - int32([xPixelOverlap/2, yPixelOverlap/2, 0]), timeIndex );
            
            %trim to border of mask
            maskBorder = false(size(byteMask));
            zMin = find(squeeze(sum(sum(byteMask,1),2)),1);
            zMax = find(squeeze(sum(sum(byteMask,1),2)),1,'last');
            xMin = find(squeeze(sum(sum(byteMask,2),3)),1) ;
            xMax = find(squeeze(sum(sum(byteMask,2),3)),1,'last') ;
            yMin = find(squeeze(sum(sum(byteMask,1),3)),1) ;
            yMax = find(squeeze(sum(sum(byteMask,1),3)),1,'last');
            maskBorder(xMin:xMax,yMin:yMax,zMin:zMax) = 1;
            byteMask = reshape(byteMask(maskBorder), xMax-xMin+1, yMax-yMin+1, zMax-zMin+1);
            imgData = reshape(imgData(repmat(maskBorder,1,1,1,6)), xMax-xMin+1, yMax-yMin+1, zMax-zMin+1,6);
            
            %visualize pixels
            %         xtTransferImageData(imgData);
            
            maskTemp{index + 1 - startIndex} = byteMask;
            imgTemp{index + 1 - startIndex} = imgData;
            
            %get surface interpolation and laser excitation
            mdString = char(md.toString);
            mdString(mdString == ' ') = '';
            mdString(mdString == '#') = '';
            mdString(mdString == ')') = '';
            mdString(mdString == '(') = '';
            md = JSON.parse(mdString);
            laser1Power = cellfun(@str2num,strsplit(md.TeensySLM1_SLM_Pattern,'-'),'UniformOutput',0);
            laser2Power = cellfun(@str2num,strsplit(md.TeensySLM2_SLM_Pattern,'-'),'UniformOutput',0);
            laser1Power = cell2mat(reshape(laser1Power(1:end-1),16,16));
            laser2Power = cell2mat(reshape(laser2Power(1:end-1),16,16));
            fovIndices = int32(round((positionUnstitched(1:2) ./ fovSize) * 15)) + 1;            
            excitations(index + 1 - startIndex,:) = [laser1Power(fovIndices(1),fovIndices(2))  laser2Power(fovIndices(1),fovIndices(2))];
            %store one copy of surface interpoaltion per a time point
            if size(saveFile, 'surfInterpPoints', 1) < timeIndex + 1 || isempty(saveFile.surfInterpPoints(timeIndex+1,1))
                interpPoints = md.DistanceFromFixedSurfacePoints;
                saveFile.surfInterpPoints = cell2mat(cellfun(@(entry) cellfun(@str2num, strsplit(entry,'_')),interpPoints,'UniformOutput',0)');
            end
        end
        
        %store masks, pixels, and other data
        saveFile.excitations(startIndex+1:endIndex+1,1:2) = excitations;
        saveFile.masks(startIndex+1:endIndex+1,1) = maskTemp;
        saveFile.imageData(startIndex+1:endIndex+1,1) = imgTemp;
        saveFile.stitchedXYZPositions(startIndex+1:endIndex+1,1:3) = [stats(find(strcmp({stats.Name},'Stitched Position X'))).Values(startIndex+1:endIndex+1),...
            stats(find(strcmp({stats.Name},'Stitched Position Y'))).Values(startIndex+1:endIndex+1),...
            stats(find(strcmp({stats.Name},'Stitched Position Z'))).Values(startIndex+1:endIndex+1)];
        
        %store surface data in file
        saveFile.vertices(size(saveFile, 'vertices', 1)+1:size(saveFile, 'vertices', 1)+size(surfList.mVertices,1),1:3) = single(vertices);
        saveFile.triangles(size(saveFile, 'triangles', 1)+1:size(saveFile, 'triangles', 1)+size(surfList.mTriangles,1),1:3) = surfList.mTriangles;
        saveFile.normals(size(saveFile, 'normals', 1)+1:size(saveFile, 'normals', 1)+size(surfList.mNormals,1),1:3) =  surfList.mNormals;
        saveFile.timeIndex(size(saveFile, 'timeIndex',1)+1 : size(saveFile, 'timeIndex',1)+length(surfList.mTimeIndexPerSurface),1) = int32(tIndices);
        saveFile.numTriangles(size(saveFile, 'numTriangles',1)+1 : size(saveFile, 'numTriangles',1)+length(surfList.mNumberOfTrianglesPerSurface),1) = surfList.mNumberOfTrianglesPerSurface;
        saveFile.numVertices(size(saveFile, 'numVertices',1)+1 : size(saveFile, 'numVertices',1)+length(surfList.mNumberOfVerticesPerSurface),1) =  surfList.mNumberOfVerticesPerSurface;
        
    end
    %write statistics for all surfaces in batch of time points
    if ~any(strcmp('stats',who(saveFile))) %store first set
        saveFile.stats = stats;
    else %append to existing
        oldStats = saveFile.stats;
        newIds = (0:(length(oldStats(1).Ids) + surface.GetNumberOfSurfaces - 1) )';
        for j = 1:length(stats)
            %modify Ids
            oldStats(j).Ids = newIds;
            %append new values
            oldStats(j).Values = [oldStats(j).Values; stats(j).Values];
        end
        saveFile.stats = oldStats;
    end
    
    saveFile.lastWrittenFrameIndex = startFrame + framesPerLoop - 1;
    
    %delete surfaces now that they're saved
    surface.RemoveAllSurfaces;
    toc
end

%Preprocess statistics for creation of design matrix
statistics = saveFile.stats;
featureNames = {statistics.Name}';
% read Imaris indices
imarisIndices = statistics(1).Ids;
%make design matrix
rawFeatures = cell2mat({statistics.Values});
xPosIdx = find(strcmp(featureNames,'Position X'));
xPosIdy = find(strcmp(featureNames,'Position Y'));
% distanceToBorder = min([rawFeatures(:,xPosIdx), rawFeatures(:,xPosIdy),...
%     max(rawFeatures(:,xPosIdx)) - rawFeatures(:,xPosIdx),  max(rawFeatures(:,xPosIdy)) - rawFeatures(:,xPosIdy) ],[],2);
inCenter = rawFeatures(:,xPosIdx) > distanceFromEdge & rawFeatures(:,xPosIdx) < (max(rawFeatures(:,xPosIdx)) - distanceFromEdge) &...
    rawFeatures(:,xPosIdy) > distanceFromEdge & rawFeatures(:,xPosIdy) < (max(rawFeatures(:,xPosIdy)) - distanceFromEdge);
%use only central surfaces
imarisIndices = imarisIndices(inCenter,:);
features = rawFeatures(inCenter,:);

saveFile.imarisIndices = imarisIndices;
saveFile.features = features;
saveFile.featureNames = featureNames;

% Copy to backup directory on different drive
% if (any(imsFilePathAndName == '\'))
%     dirs = strsplit(imsFilePathAndName,'\');
% else
%     dirs = strsplit(imsFilePathAndName,'/');
% end
% copyfile(saveName, strcat(backupDirectory,dirs{end-1},'_',dirs{end},'_',char(surfName),'.mat') );

mmData.close;
clear mmData;

    function [newStats] = modify_stats_for_stitched_view(stats)
        newStats = stats;
        pxIdx = find(ismember({stats.Name},'Position X'));
        pyIdx = find(ismember({stats.Name},'Position Y'));
        pzIdx = find(ismember({stats.Name},'Position Z'));
        tIdxIdx = find(ismember({stats.Name},'Time Index'));
        
        %rename original position stats
        % newStats(pxIdx).Name = 'Tile Position X';
        % newStats(pyIdx).Name = 'Tile Position Y';
        % newStats(pzIdx).Name = 'Tile Position Z';
        
        timeIndex = newStats(tIdxIdx).Values;
        %time index stat is one based, so subtract one
        stitchedTimeIndex = mod(timeIndex - 1,numTimePoints);
        %add actual time index in
        newStats(tIdxIdx).Values = stitchedTimeIndex;
        
        posIndices = floor(double(timeIndex - 1) ./ numTimePoints);
        posIndicesCell = num2cell(posIndices);
        
        rows = cellfun(@(index) posList.get(index).getInt('GridRowIndex'),posIndicesCell);
        cols = cellfun(@(index) posList.get(index).getInt('GridColumnIndex'),posIndicesCell);
        %calculate offset to translate from individual field of view to proper
        %position in stitched image
        offsets = [(cols * (imageWidth - xPixelOverlap)) * pixelSizeXY, (rows * (imageHeight - yPixelOverlap)) * pixelSizeXY];
        
        singlestruct = @(name, values) struct('Ids',newStats(1).Ids,'Name',name,'Values',values,'Units','');
        
        newStats(length(newStats) + 1) = singlestruct('Stitched Position X',newStats(pxIdx).Values + offsets(:,1));
        newStats(length(newStats) + 1) = singlestruct('Stitched Position Y',newStats(pyIdx).Values + offsets(:,2));
        newStats(length(newStats) + 1) = singlestruct('Stitched Position Z',newStats(pzIdx).Values );
        
        %sort into alphabetical order
        [~, statOrder] = sort({newStats.Name});
        newStats = newStats(statOrder);
    end
end

function [ pixelData, metadata ] = readRawMagellan( magellanDataset, surfaceMask, offset, timeIndex )
%return metadata from middle requested slice
%offset is in in 0 indexed pixels
%timeIndexStarts with 0
unsign = @(arr) uint8(bitset(arr,8,0)) + uint8(128*(arr < 0));

metadata = [];
%Read raw pixels from magellan
%take stiched pixels instead of decoding position indices
pixelData = zeros(size(surfaceMask,1),size(surfaceMask,2),size(surfaceMask,3),6, 'uint8');
for channel = 0:5
    for relativeSlice = 0:size(surfaceMask,3)-1
        slice = offset(3) + relativeSlice;
        ti = magellanDataset.getImageForDisplay(channel, slice, timeIndex, 0, offset(1), offset(2),...
            size(pixelData,1), size(pixelData,2));
        pixels = reshape(unsign(ti.pix),size(pixelData,1),size(pixelData,2));
        if (isempty(metadata) && floor(size(surfaceMask,3)/2) == relativeSlice )
            metadata = ti.tags;
        end
        pixelData(:,:,relativeSlice+1,channel+1) = pixels;
    end
end

end


function [newVertices, newTimeIndex] = modify_surfaces_for_stitched_view(vertices, timeIndex, numVertices, posList, imageWidth, imageHeight,...
    xPixelOverlap, yPixelOverlap, pixelSize, numTimePoints)

newVertices = zeros(size(vertices));
newTimeIndex = zeros(size(timeIndex));

%go through each surface and add it to the new surfaces as appropriate
posIndices = floor(double(timeIndex) ./ numTimePoints);

surfCount = 0;
while surfCount < length(timeIndex)
    %process in batches with same positon index (which means same offset in
    %larger sitched image)
    numInBatch = find(posIndices(1 + surfCount:end) ~= posIndices(1 + surfCount),1) - 1;
    if (isempty(numInBatch))
        numInBatch = length(posIndices) - surfCount; %last batch
    end
    verticesInBatch = sum(numVertices(1+surfCount:surfCount+numInBatch));
    firstVertex = 1 + sum(numVertices(1:surfCount));
    
    
    %offsets for spots in the larger stitched image
    row = posList.get(posIndices(1 + surfCount)).getInt('GridRowIndex');
    col = posList.get(posIndices(1 + surfCount)).getInt('GridColumnIndex');
    %calculate offset to translate from individual field of view to proper
    %position in stitched image
    offset = [(col * (imageWidth - xPixelOverlap)) * pixelSize, (row * (imageHeight - yPixelOverlap)) * pixelSize, 0];
    
    %modify vertices and time
    newVertices(firstVertex:firstVertex+verticesInBatch - 1,:) = vertices(firstVertex:firstVertex+verticesInBatch - 1,:) + repmat(offset,verticesInBatch,1);
    newTimeIndex(1+surfCount:surfCount+numInBatch) = mod(timeIndex(1+surfCount:surfCount+numInBatch),numTimePoints);
    
    surfCount = surfCount + numInBatch;
end

end

