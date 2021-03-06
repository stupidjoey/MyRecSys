clear;
tic;

%% 最后一版 主函数


%% **************对文件导入和存储的目录及名称做设定*********************************
date='10.27';

for version=1:30
% version=1;   % 第几套数据集

fprintf('---------------the current version is %d ----------------- \n',version);

% heightList= [12,14];
% widthList= [12,14];
% for it=1:2
% height=heightList(it);
% width=widthList(it);

width=10;
height=8;


fprintf('current map is %d x %d \n', width,height);

ratingSomFileName=sprintf('..\\..\\..\\data\\flixster\\somdata\\flixster_%dx%d_som%d.mat',width,height,version); 
testSetFileName=sprintf('..\\..\\..\\data\\flixster\\commondata\\testSet%d.txt',version);
resultFileName=sprintf('..\\..\\..\\result\\flixster\\som\\flixster_som_result_%d_%s.txt',version,date);

userLevelFileName=sprintf('..\\..\\..\\data\\flixster\\commondata\\userLevel%d.txt',version);
saveRecListFileName=sprintf('..\\..\\..\\data\\flixster\\somdata\\recList\\reclist%d.mat',version);
weightFileName = sprintf('..\\..\\..\\data\\flixster\\commondata\\weight_%dx%d_%d.mat',width,height,version);
userRatingMatrixFileName=sprintf('..\\..\\..\\data\\flixster\\commondata\\userRatingMatrix%d.mat',version);
socialTrustFileName=sprintf('..\\..\\..\\data\\flixster\\commondata\\trust200_direct%d.txt',version);
userSocialTrustCellFileName=sprintf('..\\..\\..\\data\\flixster\\commondata\\userSocialTrustCell_direct%d.mat',version);



%% ********************导入之前构建好的数据**********************************

load(ratingSomFileName, 'uniqUserData', 'uniqItemData', 'itemClassIndex');
load(userRatingMatrixFileName,'userRatingMatrix');
testSet = load(testSetFileName);
socialTrustData=load(socialTrustFileName);
userLevel=load(userLevelFileName);
load(weightFileName,'local_weight','global_weight');


%% ******************进行初始化***************************

userCount=length(uniqUserData);
itemCount=length(uniqItemData);
testUserData=testSet(:,1);
uniqTestUserData=unique(testUserData);
testUserCount=length(uniqTestUserData);
interestCount=size(local_weight,1);
levelNum=length(unique(userLevel(:,2)));

% 一些较为固定的参数
likeThreshold=4;   % 判断用户是否喜欢一个item的阈值，要大于它
recThreshold=0;  % 基于最终兴趣进行推荐时，在每个兴趣圈里，预测评分要大于这个阈值才会被推荐
alpha=0.5; % 兴趣合并的参数，rating=alpha，social=1-alpha
interestCircleThreshold=0.0;  % 过滤兴趣用户的阈值，大于这个值的用户归入到兴趣圈
majorInterestThreshold=0.00;  % 考虑是否是主要兴趣
beta = 0.10;

% 取得用户的trust列表
load(userSocialTrustCellFileName);
% userSocialTrustCell=GetUserSocialTrust(uniqUserData,socialTrustData);
% save(userSocialTrustCellFileName,'userSocialTrustCell');

% 将所有用户划分到不同兴趣簇中去，不同簇之间用户可以重叠
userInterestCircleCell=SplitUserByInterestCircle(global_weight,interestCircleThreshold);

% 将所有item划分到不同兴趣簇中，簇之间item不重叠
itemInterestCircleCell=SplitItemByInterestCircle(itemClassIndex,interestCount);

% 获得所有用户平均打分
userAvgRating=GetAllUserAvgRating(userRatingMatrix);

%% **** 多个参数组 *******

%% ***************参数设置及一些初始化工作*********************
socialNeighbourNum=50 ; % social friend 不超过多少个
topKList=(10:10:100);
fprintf('current social neighbour is %d \n',socialNeighbourNum)

recListLengthRecord=[]; % 记录一下每个用户的推荐列表的长度，方便调整topK
% 记录对每个用户的推荐列表

allUserRecInfo = cell(testUserCount,1);  

totalPrecision = zeros(1,10);
totalRecall = zeros(1,10);

totalCount=0; %作为最后计算precision,recall ,f1的分母
notCount = 0; % 测试集里面没有评分大于等于4的

fprintf('start the iteration ... \n')

%% *******************开始迭代************************
parfor i=1:testUserCount

    the20num=round(0.2*testUserCount);
    if mod(i,the20num)==0
        disp ('20%');
    end
    %% ***********对每个目标用户进行一些初始化****************
    
    % 待推荐用户ID
    testUser=uniqTestUserData(i);
    % 从训练集中的uniqUserData找 testuser对应的ID
    testUserID=find(uniqUserData == testUser);
 
    levelIdx=find(userLevel(:,1)==testUser);
    level=userLevel(levelIdx,2);
  
    %% *********************************迭代第一步，取得目标用户的推荐列表*********************
    
    %% ***********取得目标用户基于评分信息得到的兴趣及权重************
    
    ratingInterestWeight=zeros(interestCount,2);
    ratingInterestWeight(:,1)=(1:interestCount);
    ratingInterestWeight(:,2)=local_weight(:,testUserID);
    
    totalGlobalInterest = global_weight(:,testUserID);
    
    % 选择大于阈值的兴趣,其他的不去掉，只是赋值为0，方便后面结合
    % ########### rating interest 暂时不过滤########################
%     idx=find(ratingInterestWeight(:,2) < majorInterestThreshold);
%     ratingInterestWeight(idx,2)=0;

    % 归一化
    totalWeight1 = sum(ratingInterestWeight(:,2));
    if totalWeight1>0
        ratingInterestWeight(:,2)=ratingInterestWeight(:,2)/totalWeight1;
    end
    
    %% ***********取得目标用户基于社交信息得到的兴趣及权重*************
    
    userSocialCircle=userSocialTrustCell{testUserID};
    
    if isempty(userSocialCircle)
        socialInterestWeight=zeros(interestCount,2);
    else
        socialFriendNum = size(userSocialCircle,1);
        if socialFriendNum>socialNeighbourNum
           realSocialNeiNum = socialNeighbourNum;
        else
           realSocialNeiNum=socialFriendNum;
        end
        userSocialCircle=userSocialCircle(1:realSocialNeiNum,:);
        socialInterestWeight = GetSocialInterestWeight(userSocialCircle,local_weight,majorInterestThreshold);
        % 归一化
        totalWeight2=sum(socialInterestWeight(:,2));
        if totalWeight2>0
            socialInterestWeight(:,2)=socialInterestWeight(:,2)/totalWeight2;
        end
    end
    
    %% ***************兴趣合并*************************
    mixedInterestWeight=zeros(interestCount,2);
    mixedInterestWeight(:,1)=(1:interestCount);
%     mixedInterestWeight(:,2)=(1-alpha)*ratingInterestWeight(:,2)+alpha*socialInterestWeight(:,2);
     mixedInterestWeight(:,2)=ratingInterestWeight(:,2);
%     mixedInterestWeight(:,2) = socialInterestWeight(:,2);

    % 去除为0的兴趣
    tx0=find(mixedInterestWeight(:,2)>0);
    mixedInterestWeight=mixedInterestWeight(tx0,:);
    % 降序排列
    mixedInterestWeight=-sortrows(-mixedInterestWeight,2);     
   
    
    % 计算所有权重的和
    totalWeight=sum(mixedInterestWeight(:,2));
    totalInterestRecList=[];
    
    maxInterest = 15;
    simpleCount =0;
    %% ************* 基于目标用户每一个兴趣产生一个推荐列表，并去除用户已经看过的 *********************
    for j=1:size(mixedInterestWeight,1)
        if simpleCount>maxInterest
            continue;
        end
        simpleCount = simpleCount+1;
        
        % 算相对权重,最后再合并各兴趣集合，要乘上去
        tempWeight = mixedInterestWeight(j,2)/totalWeight;
        % 获取在该兴趣圈的里的人
        userInterestCircle = userInterestCircleCell{mixedInterestWeight(j,1)};
        interestNo = mixedInterestWeight(j,1);
        globalPrefer = totalGlobalInterest(interestNo);
        
        % 注意兴趣圈为空的情况
        if isempty(userInterestCircle)
            continue
        end
        % 在兴趣小组中去除自己
        idx1=find(userInterestCircle(:,1) == testUserID);
        userInterestCircle(idx1,:)=[];
        % 获取划分到该兴趣圈的item
        itemInterestCircle=itemInterestCircleCell{mixedInterestWeight(j,1)};
        if isempty(itemInterestCircle)
            continue
        end
        % *****基于兴趣进行推荐******     
        % ################### 注：暂时不用预测评分的大小来过滤 ##########################
        interestRecList = GetRecListByInterestCircle2(testUserID,userInterestCircle,itemInterestCircle,userRatingMatrix,globalPrefer,beta);
                           
        % 评分要乘以这个圈子的相对权重
        interestRecList(:,2)=interestRecList(:,2)*tempWeight;
               
        % 补充加一个备注，包含item所属的兴趣类别ID，到时候再改回来
        completeInterestRecList = zeros(size(interestRecList,1),3);
        completeInterestRecList(:,1:2) = interestRecList(:,1:2);
        completeInterestRecList(:,3) = mixedInterestWeight(j,1);
        % 汇总各个兴趣圈子的结果
        
        totalInterestRecList=[totalInterestRecList; completeInterestRecList];
    end   
    
     % 记录一下每个用户的推荐列表的长度，方便调整topK
    recListLengthRecord=[recListLengthRecord; [testUser size(totalInterestRecList,1)]];
    
    finalRecList = cell(10,1);
    % 对合并后的推荐列表按打分高低进行排序，降序排列
    if ~isempty(totalInterestRecList)
        totalInterestRecList=-sortrows(-totalInterestRecList,2);
         % 去除testUser已经看过的
        watchedItemList=find(userRatingMatrix(testUserID,:)>0);
        [c,ia]=intersect(totalInterestRecList(:,1),watchedItemList);
        totalInterestRecList(ia,:)=[];
         % 对topK的设置，不够就不够了
         
        for m = 1:10  
            if length(totalInterestRecList(:,1))<topKList(m)
                realTopK = length(totalInterestRecList(:,1));
                finalRecList{m}= totalInterestRecList(1:realTopK,1);
            else
                finalRecList{m} = totalInterestRecList(1:topKList(m),1);
            end
        end
        
    end
       
    
    %% **********************************迭代第二步，取得测试集中目标用户喜欢的item列表***********************
    % 以评分大于likeThreshold表示喜欢
    tempIndex=find(testSet(:,1)==testUser & testSet(:,3)>=likeThreshold);
    tempItemSet=testSet(tempIndex,2);
    
    [commonItem,IA,IB]=intersect(uniqItemData,tempItemSet);
    testUserLikedItemList=IA;
        
    if isempty(testUserLikedItemList)
        % 测试集用户中没有评分大于3的item，则不考虑这个用户的推荐，放弃推荐
        notCount = notCount+1;
        continue;       
    end
    
    %% **************************************迭代第三步，评测推荐效果****************************************
    % 将推荐列表和测试集中用户喜欢的item取交集，即为hit个数
    precisionList= [];
    recallList = [];

    for m = 1:10
        if isempty(finalRecList{m})
            hitList = [];
            % 计算单个用户的precision和recall
            precision = 0;
            recall = 0 ;
        else
            [hitList,iia,iib] = intersect(finalRecList{m},testUserLikedItemList);
            % 计算单个用户的precision和recall
            precision=length(hitList)/topKList(m);
            recall=length(hitList)/length(testUserLikedItemList);
        end
        if isnan(recall) || isnan(precision)
            disp('there is something wrong with the recall or the precision');
        end
        precisionList = [precisionList precision];
        recallList = [recallList recall];     
    end
    
    totalPrecision = totalPrecision + precisionList;
    totalRecall = totalRecall + recallList;
    
        
    % 记录每个用户的最终的推荐列表
    infoCell = cell(1,5);   
    infoCell{1} = testUser;
    infoCell{2} = testUserID;
    infoCell{3} = level;
    infoCell{4} = testUserLikedItemList;
    infoCell{5} = finalRecList{10};   
    allUserRecInfo{i} = infoCell;
    
    % 跑到最后的，计数+1，最后作为分母
    totalCount=totalCount+1;
end

%% #####################评价指标###########################

avgPrecision=totalPrecision/totalCount;
avgRecall=totalRecall/totalCount;
avgF1=2*avgPrecision.*avgRecall./(avgPrecision+avgRecall);


% **********final 实验用 ***************
for m =1 :10
    topK = topKList(m);
    finalResultFileName=sprintf('..\\..\\..\\result\\flixster\\som\\pbmim\\final_flixster_pbmim_prf_top%d.txt',topK);
    fid = fopen(finalResultFileName,'a');
    fprintf(fid,'%f\t%f\t%f\r\n',avgPrecision(m),avgRecall(m),avgF1(m));
    fclose(fid);
end


allUserRecInfoFile = sprintf('..\\..\\..\\result\\flixster\\som\\pbmim\\allUserRecInfo%d.mat',version);
save(allUserRecInfoFile,'allUserRecInfo');



% end
end

toc;

