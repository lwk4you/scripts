dir="$1"
project="$2"
gitRepo="$3"
gitUser="$4"
gitPassword="$5"
args="$6"
gitBranch="$7"

urlencode() {
    # urlencode <string>
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C

    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
    LC_COLLATE=$old_lc_collate
}

source /etc/profile
mkdir -p $dir



# 开始拉取代码
gitRepoSplit=($(echo $gitRepo | perl -nE 'print "$1\n$2" if /^(.*?)\/\/(.*)$/'))
gitUserEnc=$(urlencode $gitUser)
gitPasswordEnc=$(urlencode $gitPassword)
gitRepoAuthed=$(echo "${gitRepoSplit[0]}//${gitUserEnc}:${gitPasswordEnc}@${gitRepoSplit[1]}")

if [[ -d "$dir/$project" && -d "$dir/$project/.git" ]]; then
    # update
    cd $dir/$project
    git pull
else
    # clone
    cd $dir
    rm -rf $project
    if [[ "$gitBranch " == " " ]]; then
        git clone --progress $gitRepoAuthed $project
    else
        git clone --progress -b $gitBranch $gitRepoAuthed $project
    fi
    cd $project
fi



# 准备 stop.sh 脚本
echo -e '
cd $(cd `dirname $0`; pwd)
if [[ -f "pid" ]]; then
    mainPid=$(cat pid)
    if [[ "$mainPid " != " " ]]; then
        relatedPids=$(ps -ef | grep "$mainPid" | awk '"'"'{print $2,$3}'"'"' | grep "$mainPid" | awk '"'"'{print $1}'"'"')
    fi
    if [[ "$relatedPids " != " " ]]; then
        echo "kill existed process $mainPid"
        kill -9 $mainPid
        
        echo -e "wait\\c"
        sleep 0.25
        
        allStop=0
        while [[ $allStop == 0 ]]; do
            allStop=1
            for pid in $relatedPids; do
                if ps -p $pid > /dev/null; then
                   echo -e ".\\c"
                   kill -9 $pid
                   allStop=0
                   break
                fi
            done
            sleep 0.5
        done
        rm -rf pid
        echo -e "\\nstopped"
    fi
fi
' > stop.sh
chmod +x stop.sh



# 准备 start.sh 脚本
echo -e '
cd $(cd `dirname $0`; pwd)
./stop.sh
# 备份日志
# if [[ -f "main.log" ]];then
#     if [[ ! -d "log_bak" ]];then
#         mkdir log_bak
#     fi
#     mv main.log log_bak/main.log.`date "+%Y%m%d_%H%M%S"`
# fi

echo -e '"'"'nohup mvn spring-boot:run '${args}' 1>>main.log 2>&1 & echo $! > pid'"'"'
nohup mvn spring-boot:run '${args}' 1>>main.log 2>&1 & echo $! > pid

# 打印main.log日志，持续120秒;通过这个进程来控制tail进程的结束
sleep 120 & echo $! > tailCtlPid

# 打印一段时间的日志，方便远程启动时判定启动是否成功
tail -f -n 0 --pid=`cat tailCtlPid` main.log | while read line; do
        if [[ "$line" = "Application startup: success." ]]; then
            cat tailCtlPid | xargs kill -9
            echo "0" > exitCode
        elif [[ "$line" = "Application startup: fail." ]] || [[ "$line" = "[ERROR]" ]]; then
            cat tailCtlPid | xargs kill -9
            echo "-1" > exitCode
        else
            echo $line
        fi
    done

rm -rf tailCtlPid
exitCode=$(cat exitCode)
rm -rf exitCode
exit $exitCode
' > start.sh
chmod +x start.sh



# 启动
./start.sh
