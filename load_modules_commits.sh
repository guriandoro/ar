#!/bin/bash

readonly mysql_command="/home/agustin.gallego/sandboxes/ps_5.7.25/use";

echo "--> Creating tables in MySQL.";
date;

# Create schema and tables needed
$mysql_command -e "CREATE SCHEMA IF NOT EXISTS ar";
$mysql_command -e "DROP TABLE IF EXISTS ar.percona_server_modules";
$mysql_command -e "CREATE TABLE ar.percona_server_modules ( \
  id int(11) NOT NULL AUTO_INCREMENT, \
  file_name varchar(255) DEFAULT NULL, \
  dependency_module_name_full text, \
  dependency_module_name text, \
  dependency_module_file_name text, \
  PRIMARY KEY (id), \
  KEY idx_file_name (file_name) \
) ENGINE=InnoDB";

$mysql_command -e "DROP TABLE IF EXISTS ar.percona_server_modules_no_match";
$mysql_command -e "CREATE TABLE ar.percona_server_modules_no_match ( \
  id int(11) NOT NULL AUTO_INCREMENT, \
  file_name varchar(255) DEFAULT NULL, \
  dependency_module_name_full text, \
  dependency_module_name text, \
  dependency_module_file_name text, \
  PRIMARY KEY (id), \
  KEY idx_file_name (file_name) \
) ENGINE=InnoDB";

$mysql_command -e "DROP TABLE IF EXISTS ar.percona_server_jira_commits";
$mysql_command -e "CREATE TABLE ar.percona_server_jira_commits ( \
  id int(11) NOT NULL AUTO_INCREMENT, \
  commit binary(20) NOT NULL, \
  files_changed text, \
  commit_text text, \
  PRIMARY KEY (id), \
  UNIQUE KEY commit (commit) \
) ENGINE=InnoDB";

$mysql_command -e "DROP TABLE IF EXISTS ar.percona_server_other_commits";
$mysql_command -e "CREATE TABLE ar.percona_server_other_commits ( \
  id int(11) NOT NULL AUTO_INCREMENT, \
  commit binary(20) NOT NULL, \
  files_changed text, \
  commit_text text, \
  PRIMARY KEY (id), \
  UNIQUE KEY commit (commit) \
) ENGINE=InnoDB";

echo "--> Iterating through files to get module dependencies.";
echo "--> Check \`tail -f /tmp/ar_modules.out\` for progress.";
date;

readonly mysql_command="/home/agustin.gallego/sandboxes/ps_5.7.25/use";

# Iterate through files getting dependencies
find . -type f | egrep "\.c$|\.cc$|\.cpp$|\.h$|\.hpp$" | {
  while read file; do {
    echo "file: " $file;
    module_name_list=`grep "^#include" $file | awk '{print $2}'`;
    echo "module_name_list: " $module_name_list;
    
    # Iterate on each module listed as dependency
    for module_name_full in $module_name_list; do {
        echo "module_name_full: " $module_name_full;
        module_name=`echo $module_name_full | sed -e "s/[<>\"]//g"`;
        echo "module_name: " $module_name;
        if [[ ${module_name} =~ .*(/.*)+ ]]; then
            module_file=`find . -path \*${module_name}`;
        else
            module_file=`find . -name ${module_name}`;
        fi

        # If we don't find an exact match, we try with a wildcard at the end
        if [[ ${module_file} =~ ^$ ]]; then
            module_file_no_match=`find . -name ${module_name}"*"`;
            # Insert into secondary table
            ${mysql_command} -e "INSERT INTO ar.percona_server_modules_no_match VALUES \
                                 (NULL, '${file}', '${module_name_full}', \
                                 '${module_name}', '${module_file_no_match}')";
            echo "module_file_no_match: " $module_file_no_match;
        else
            # Insert into main table
            ${mysql_command} -e "INSERT INTO ar.percona_server_modules VALUES \
                                 (NULL, '${file}', '${module_name_full}', \
                                 '${module_name}', '${module_file}')";
            echo "module_file: " $module_file;
        fi

    } done;
  } done;
} > /tmp/ar_modules.out 2>&1

echo "--> Iterating through commits to get relevant information.";
echo "--> Check \`tail -f /tmp/ar_commits.out\` for progress."
date;

git rev-list --no-merges HEAD | {
    while read commit; do {
        files_in_commit=`git diff-tree --no-commit-id --name-only -r $commit | tr '\n' ' '`;
        # Check if (case insensitive match) PS-x appears on the commit message,
        # where x is one or more digits. If so, it's most likely a reference to a Jira bug
        git show --pretty=tformat:%B -s $commit | egrep -i "(ps-[0-9]+)" >/dev/null;
        egrep_exit_status=$?;
        commit_text=`git show --pretty=tformat:%B -s $commit | sed -e "s/[\"\']//g"`;
        
        if [[ $egrep_exit_status -eq 0 ]]; then
            # If there is a match, we log that commit to JIRA's table    
            echo "Inserting commit JIRA: " ${commit};
            ${mysql_command} -e "INSERT INTO ar.percona_server_jira_commits VALUES \
                                 (null, unhex('$commit'), '${files_in_commit}', '${commit_text}')";
        else
            # Otherwise, we log that commit to the generic table
            echo "Inserting commit generic: " ${commit};
            ${mysql_command} -e "INSERT INTO ar.percona_server_other_commits VALUES \
                                 (null, unhex('$commit'), '${files_in_commit}', '${commit_text}')";
        fi 
    } done;
} > /tmp/ar_commits.out 2>&1

echo "--> Finished processing modules and commits";
date;

exit 0;

# We also need to delete rows where there is more than one match
# delete from percona_server_modules where dependency_module_file_name like '%\n%';

