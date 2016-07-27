clear
clc

aImarisApplicationID = 0;
directory = '/Users/henrypinkard/Desktop/LNData/TimeProjections/';
radius = 30;
xyDownsample = 10;

%make sure the matlab librarypath.txt file is set correctly for JNI calls
javaaddpath jarh5obj.jar;
javaaddpath jarhdf5-2.10.0.jar;
javaaddpath jarhdfobj.jar;
javaaddpath xt/Imaris_writer.jar;
javaaddpath xt/ImarisLib.jar;
% javaaddpath('C:\Users\hpinkard\Dropbox\Henry\Code\Matlab\time projection\jhdf.dll');
% javaaddpath('C:\Users\hpinkard\Dropbox\Henry\Code\Matlab\time projection\jhdf5.dll');

vImarisLib = ImarisLib;
imarisApplication = vImarisLib.GetApplication(aImarisApplicationID);
vDataSet = imarisApplication.GetDataSet;


objects = imarisApplication.GetFactory.ToSurfaces(imarisApplication.GetSurpassSelection);



spotTimeIndices = spots.GetIndicesT;
spotUmCoords = spots.GetPositionsXYZ;
spotsName = spots.GetName;
%transform to pixel coordinates
vDataMin = [vDataSet.GetExtendMinX, vDataSet.GetExtendMinY, vDataSet.GetExtendMinZ];
vDataMax = [vDataSet.GetExtendMaxX, vDataSet.GetExtendMaxY, vDataSet.GetExtendMaxZ];
vDataSize = [vDataSet.GetSizeX, vDataSet.GetSizeY, vDataSet.GetSizeZ];
pixelSizeZ = (vDataMax(3) - vDataMin(3)) / vDataSize(3);
pixelSizeXY = (vDataMax(2) - vDataMin(2)) / vDataSize(2);

pixelSizeXY = pixelSizeXY * xyDownsample;

%add 1 to pixels to account for Matlabs one based indexing
spotPixelCoords = floor(spotUmCoords ./ repmat([pixelSizeXY pixelSizeXY pixelSizeZ],size(spotUmCoords,1),1)) + 1;
slices = vDataSet.GetSizeZ;
frames = vDataSet.GetSizeT;
width = floor(vDataSet.GetSizeX / xyDownsample);
height = floor(vDataSet.GetSizeY / xyDownsample);
prefix = strcat(spotsName,sprintf('_%d um %d timepoint time projection',radius,timepoints_to_project));
imarisWriter = HDF.ImarisWriter(directory,prefix,width,height,slices,1,frames,pixelSizeXY,pixelSizeZ,[]);


vProgressDisplay = waitbar(0, 'Creating time projection');

%add blank pixels to first (timepoint to project)
for frame = 0:frames-1
    if frame < timepoints_to_project-1
        pixels = zeros(width, height, slices, 'uint8');
        for s = 0:slices-1
            %add slice to storage
            imarisWriter.addImage(reshape(pixels(:,:,s+1),1,width*height),s,0,frame,[],vDataSet.GetTimePoint(frame));
        end
    else
        sprintf('frame: %d',frame)
        %get the set of spots for this and previous n timepoints
        startTimeIndex = frame - (timepoints_to_project-1);
        endTimeIndex = frame;
        
        spotsInWindow = spotPixelCoords(spotTimeIndices >= startTimeIndex & spotTimeIndices <= endTimeIndex,:);
        
        %create empty pixel data
        pixels = zeros(width, height, slices, 'uint8');
        
        pixelRadiusXY = radius / pixelSizeXY;
        pixelRadiusZ = radius / pixelSizeZ;
        for i = 1:size(spotsInWindow,1)
            %add to pixel values in time projection channel based on coordinates
            %of spot
            for x = max(1,spotsInWindow(i,1) - pixelRadiusXY):min(size(pixels,1), spotsInWindow(i,1) + pixelRadiusXY)
                for y = max(1,spotsInWindow(i,2) - pixelRadiusXY): min(size(pixels,2), spotsInWindow(i,2) + pixelRadiusXY)
                    for z = max(1,spotsInWindow(i,3) - pixelRadiusZ):min(size(pixels,3), spotsInWindow(i,3) + pixelRadiusZ)
                        %iterating through a 3D rectangle of all possible pixels,
                        %increment only those that lie within inscribed ellipsoid
                        %subtract one and multiply by pixel size to get um position
                        if sqrt(sum([pixelSizeXY*((x-1) - spotsInWindow(i,1)) pixelSizeXY*((y-1) - spotsInWindow(i,2))...
                                pixelSizeZ*((z-1) - spotsInWindow(i,3))].^2)) < radius
                            indices = round([x y z]);
                            pixels(indices(1), indices(2), indices(3)) = pixels(indices(1), indices(2), indices(3)) + 1;
                        end
                    end
                end
            end
            sprintf('frame: %d\t\tspot: %d of %d',frame,i,size(spotsInWindow,1))
        end
        
        %write pixels to tiff storage
        for s = 0:slices-1
            %add slices
            imarisWriter.addImage(reshape(pixels(:,:,s+1),1,width*height),s,0,frame,[],vDataSet.GetTimePoint(frame));
        end
    end
    waitbar(frame/frames, vProgressDisplay)
end


%close hdfWriter
imarisWriter.close();

close(vProgressDisplay);