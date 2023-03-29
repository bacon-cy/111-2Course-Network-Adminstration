#!/usr/local/bin/bash

#usage : print out help message
usage() {
echo -n -e "\nUsage: sahw2.sh {--sha256 hashes ... | --md5 hashes ...} -i files ...\n\n--sha256: SHA256 hashes to validate input files.\n--md5: MD5 hashes to validate input files.\n-i: Input files.\n"
}


#
# Parsing Options
#

md5=0
sha256=0
declare -i filenum=0
declare -i hashnum=0
files=()
hashes=()

#沒有給參數
if [ $# -le 0 ]; then
	usage
	exit 1
fi

while [ "$#" -gt 0 ]; do
	case "$1" in
		-h) #help
			usage
			exit 0
		;;
		-i) #input files
			shift
			while [ $# -gt 0 ] && ! [[ "$1" == -* ]]; do
                files+=("$1")
				filenum=$(( filenum + 1 ))
				shift
			done
		;;
		--md5)
			md5=1
			shift
			while [ $# -gt 0 ] && ! [[ "$1" == -* ]]; do
				hashes+=("$1")
				hashnum=$(( hashnum + 1 ))
				shift
			done
		;;
		--sha256)
			sha256=1
			shift
			while [ $# -gt 0 ] && ! [[ "$1" == -* ]]; do
				hashes+=("$1")
				hashnum=$(( hashnum + 1 ))
				shift
			done
		;;	
		*) #invaid options inputed
			if [[ "$1" != "-md5" ]] && [[ "$1" != "-sha256" ]]; then
			echo -n "Error: Invalid arguments." 1>&2
			usage
			exit 1
			fi
		;;
	esac
done

if [ $hashnum -ne $filenum ]; then
	echo -n "Error: Invalid values." 1>&2
	exit 2
fi
	
if [ $md5 -eq 1 ] && [ $sha256 -eq 1 ]; then
	echo -n "Error: Only one type of hash function is allowed." 1>&2
	exit 3
fi


#
# Hash Validation
#

for i in $(seq 0 $(($filenum- 1))); do
    if [ $md5 -eq 1 ]; then
        cal_hash=$( md5sum "${files[$i]}" | awk '{print $1}' )
    elif [ $sha256 -eq 1 ]; then
        cal_hash=$( sha256sum "${files[$i]}" | awk '{print $1}' )
    fi
    
    #比對cal_hash和hashes[i]是否相同
    if ! [ "$cal_hash" == "${hashes[$i]}" ]; then
        echo -n "Error: Invalid checksum." 1>&2
        exit 4
    fi
done


#
# Parsing JSON & CSV
#
users=()
password=()
shell=()
groups=()

for i in $(seq 0 $(($filenum - 1))); do
    json=0
    csv=0
    file_content=$( cat "${files[$i]}" )

    #Check File is valid or not
    if [ $( file "${files[$i]}" | grep JSON >/dev/null 2>&1; echo $? ) -eq 0 ]; then
        json=1
    elif [ $( file "${files[$i]}" | grep CSV >/dev/null 2>&1; echo $? ) -eq 0 ]; then
        csv=1
    else
        echo -n "Error: Invalid file format." 1>&2
        exit 5
    fi

    #Process CSV
    if [ $csv == 1 ]; then    
        users+=`sed -e '1d' ${files[$i]} | awk -F',' '{print $1 " "}'`
    #Process JSON
    else
        users+=`jq '.[] | .username' ${files[$i]} | sed -e 's/\"/ /g'`
    fi
    
done


echo -n 'This script will create the following user(s): '
for u in $users; do
    echo -n "$u"' '
done
echo -n 'Do you want to continue? [y/n]:'

read ans
case $ans in
    n | \n)
        exit 0  
    ;;
    [^y])
        exit 8
esac



#
# Add Users
#

check_user(){
    user_exist=`id "$1" >/dev/null 2>&1; echo $?`
    if [ $user_exist -eq 0 ]; then
        echo -n "Warning: user $1 already exists." 1>&2
        return 1
    fi
    return 0
}

check_group(){
    group_exist=`pw group show -a | grep "$1" >/dev/null 2>&1; echo $?`
    if [ $group_exist -ne 0 ]; then
        pw groupadd "$1" >/dev/null 2>&1
    fi
}

adduser_json(){
    for user_info in $(jq -c '.[]' "$1");do
        username=$(jq '.username' <<< "$user_info" | tr -d '"')
        password=$(jq '.password' <<< "$user_info" | tr -d '"')
        shell=$(jq '.shell' <<< "$user_info" | tr -d '"')
        groups=$(jq '.groups' <<< "$user_info" | tr -d '"' | tr -d '[' | tr -d ']' | tr -d ' ' | tr -d '\n')
        user_exist=$(check_user "$username" | echo $?)
        if [ $user_exist -eq 1 ]; then
            continue
        fi
        for g in "$(echo $groups | sed -e 's/,/ /g')"; do
            check_group $g
        done
        pw useradd "$username" -G "$groups" -w no
        echo "$password" | passwd "$username" 
    done
}

adduser_csv(){
    cat $1 | while read -r user_info; do
        
    done 
}

for i in ${files[@]}; do
    if [ `file $i | grep JSON >/dev/null 2>&1; echo $?` -eq 0 ];then
        adduser_json $i
    else
        adduser_csv $i
    fi
done

