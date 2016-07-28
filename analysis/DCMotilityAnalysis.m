clear
load ('DCs_tracks.mat');

figure(1)
%plot number of tracked cells at each time point
allData = cell2mat(tracks);
histogram([allData.t], range([allData.t])+1)

deltaTh = deltaTmin / 60;
%get displacements for each track 
getDispSq = @(track) sum((cat(1,track.xyz) - repmat(track(1).xyz,size(cat(1,track.xyz),1),1)).^2,2);
tracksDispSq = cellfun(getDispSq,tracks,'UniformOutput',false);
figure(1)
singleTrackDispSq = tracksDispSq{1};
plot(deltaTh * [tracks{1}.t],singleTrackDispSq)
hold on
for i = 2:length(tracksDispSq)
    singleTrackDispSq = tracksDispSq{i};
    plot(deltaTh * [tracks{i}.t],singleTrackDispSq,'.-')
end
hold off
ylabel('Displacement^2 (\mum^2)')
xlabel('Time (h)')
exportPlot('DC displacementSq')


%velocity vs time
figure(2)
getVelocity = @(track) sqrt(sum((cat(1,track(2:end).xyz) - cat(1,track(1:end-1).xyz)).^2,2))/deltaTh;
velocities = cellfun(getVelocity,tracks,'UniformOutput',false);
avgSpeed = zeros(max([allData.t]),1);
stdError = zeros(max([allData.t]),1);
for t = 1:length(avgSpeed)
    %find velocity for all tracks at timepoint
    vAtTP = cellfun(@(track,speed) speed(find([track(2:end).t]==t,1)),tracks,velocities,'UniformOutput',false);
    vAtTP = cell2mat(vAtTP(~cellfun(@isempty,vAtTP)));  %ignore missing tracks
    avgSpeed(t) = mean(vAtTP);
    stdError(t) = std(vAtTP) / sqrt(length(vAtTP)-1);
end
errorbar((1:length(avgSpeed))*deltaTh,avgSpeed,stdError)
ylabel('Velocity (\mum/h)')
xlabel('Time (h)')
exportPlot('DC velocities')

%Directions of movement vs chemokine gradients
figure(3)
tracks = getChemokineAndMigrationVecs(tracks);
% for i = 


plot([tracks{7}.migGradAngle])

