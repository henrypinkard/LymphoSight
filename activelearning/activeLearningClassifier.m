function [ output_args ] = activeLearningClassifier(  )
%ACTIVELEARNINGCLASSIFIER Master function for querying user and classifying surfaces
% This function loads an unlabelled nxp data matrix and prompts the user
% for labeling of examples so that it can learn and generalize to the full
% dataset as fast as possible
%
%
% CONTROLS:
% 1 - Enter active learning mode: begin presenting unlabelled examples at
% current time point
% 2 - Classify and visualize all instances at current time point
% 3 - Activate crosshair selection mode to manually select an instance to
% classify (needed if for example, the active learning struggles with a
% particular cell
% y - Yes the currently presented instance show be laballed as a T cell
% n - No the currently presented instance in not a T cell


dataFile = '/Users/henrypinkard/Google Drive/Research/BIDC/LNImagingProject/data/CMTMRFeaturesAndLabels.mat';
surfaceFile = '/Users/henrypinkard/Desktop/LNData/CMTMRCandidates.mat';
%load features and known labels
featuresAndLabels = matfile(dataFile,'Writable',false);
%Load surface data into virtual memory
surfaceData = matfile(surfaceFile,'Writable',false);

%Connect to Imaris
[ xImarisApp, xPreviewSurface, xPopulationSurface, xSurfaceToClassify ] = xtSetupSurfaceTransfer(  )
xSurpassCam = xImarisApp.GetSurpassCamera;

%create figure for key listening
figure(1);
title('Imaris bridge');
set(gcf,'KeyPressFcn',@keyinput);
surfaceClassicationIndex_ = -1;


    function [] = presentNextExample()
%         xImarisApp
        
        surfaceClassicationIndex_ = nextSampleToClassify( features, labelledTCell, labelledNotTCell );
        func_addsurfacestosurpass(xImarisApp,surfFile,1, imarisIndices(surfaceClassicationIndex_));
        centerToSurface(xSurfaceToClassify);
    end

%Controls
    function [] = keyinput(~,~)
        key = get(gcf,'CurrentCharacter');
        if strcmp(key,'1')
            % Enter active learning mode: begin presenting unlabelled examples at current time point
            presentNextExample();
        elseif strcmp(key,'2')
            % 2 - Classify and visualize all instances at current time point
            
        elseif strcmp(key,'3')
            % 3 - Activate crosshair selection mode to manually select an instance to classify
            
        elseif strcmp(key,'y')
            %Yes the currently presented instance show be laballed as a T cell
            labelledTCells = unique([labelledTCells surfaceClassicationIndex_]);
             presentNextExample();
        elseif strcmp(key,'n')
            %Yes the currently presented instance show be laballed as a T cell
            labelledNotTCells = unique([labelledNotTCells surfaceClassicationIndex_]);
            presentNextExample();
        end
    end

%surpass camera parameters:
%height--distance from the object it is centered on, changes with zoom but not with rotation
%position--camera position, not related to center of rotation
%focus--seemingly not related to anything... (maybe doesn't matter for orthgraphic)
%Fit will fit viewing frame around entire image...which will in turn set the center of rotation to the center of image
    function [] = centerToSurface(surface)
        %get initial height for resetting
        height = xSurpassCam.GetHeight;
        %Oreint top down
        xSurpassCam.SetOrientationQuaternion(quatRot(pi,[1; 0; 0])); %top down view
        %Make center of rotation center of entire image
        xSurpassCam.Fit;
        currentCamPos = xSurpassCam.GetPosition;
        previewPos = surface.GetCenterOfMass(0);
        xSurpassCam.SetPosition([previewPos(1:2), currentCamPos(3) ]); %center camera to position of preview surface
        xSurpassCam.SetHeight(height);
        %make sure preview is visible
        surface.SetVisible(true);
    end

    function [ xImarisApp, xPreviewSurface, xPopulationSurface, xSurfaceToClassify ] = xtSetupSurfaceTransfer(  )
        previewName = 'Preview surface';
        populationName = 'TCells';
        surfaceToClassifyName ='SurfaceToClassify';
        
        xtIndex = 0;
        javaaddpath('../xt/ImarisLib.jar')
        vImarisLib = ImarisLib;
        xImarisApp = vImarisLib.GetApplication(xtIndex);
        if (isempty(xImarisApp))
            error('Wrong imaris index');
        end
        
        xSurpass = xImarisApp.GetSurpassScene;
        %delete old surface preview
        for i = xSurpass.GetNumberOfChildren - 1 :-1: 0
            if (strcmp(char(xSurpass.GetChild(i).GetName),previewName) || strcmp(char(xSurpass.GetChild(i).GetName),populationName)...
                    || strcmp(char(xSurpass.GetChild(i).GetName),surfaceToClassifyName))
                xSurpass.RemoveChild(xSurpass.GetChild(i));
            end
        end
        xPreviewSurface = xImarisApp.GetFactory.CreateSurfaces;
        xPreviewSurface.SetName(previewName);
        xSurpass.AddChild(xPreviewSurface,-1);
        xPopulationSurface = xImarisApp.GetFactory.CreateSurfaces;
        xPopulationSurface.SetName(populationName);
        xSurpass.AddChild(xPopulationSurface,-1);
        xSurfaceToClassify = xImarisApp.GetFactory.CreateSurfaces;
        xSurfaceToClassify.SetName(surfaceToClassifyName);
        xSurpass.AddChild(xSurfaceToClassify,-1);
    end


% quaternion functions %
%multiply 2 quaternions
quatMult = @(q1,q2) [ q1(4).*q2(1:3) + q2(4).*q1(1:3) + cross(q1(1:3),q2(1:3)); q1(4)*q2(4) - dot(q1(1:3),q2(1:3))];
%generate a rotation quaternion
quatRot = @(theta,axis) [axis / norm(axis) * sin(theta / 2); cos(theta/2)];
%Rotate a vector and return a quaternion, which then needs to be subindexed
%to get a vector again
rotVect2Q = @(vec,quat) quatMult(quat,quatMult([vec; 0],[-quat(1:3); quat(4)]));

end