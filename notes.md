ls -1 | grep -v stdout | grep -v stderr | cut -d '@' -f 1 | sort | uniq -c | awk -v limit=1 '$1 > limit{print $2}' | while read l ; do files="$(find . -name "$l*" -not -name "*stdout*" -not -name "*stderr*" -exec echo \{\} \;)" ; file1=$(echo "$files" | sed -n 1,1p) ; file2=$(echo "$files" | sed -n 2,2p) ; if grep -q "job exit code: 0" "$file1" ; then mv -v "$file2" "$file2".reject ; else mv -v "$file1" "$file1".reject ; fi ; done


find . -name "*.log" -not -name "*stdout*" -not -name "*stderr*" -exec  grep "job exit code: 1" {} \;


find . -name "*.log" -not -name "*stdout*" -not -name "*stderr*" -exec  grep -L  "handler finished, code= 0" {} \;