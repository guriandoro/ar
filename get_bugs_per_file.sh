#!/bin/bash

readonly mysql_command="/home/agustin.gallego/sandboxes/ps_5.7.25/use";

# Create schema and tables needed
$mysql_command -e "CREATE SCHEMA IF NOT EXISTS ar";
$mysql_command -e "DROP TABLE IF EXISTS ar.percona_server_file_severity";
$mysql_command -e "CREATE TABLE ar.percona_server_file_severity ( \
  id int(11) NOT NULL AUTO_INCREMENT, \
  file_name varchar(255) DEFAULT NULL, \
  severity int DEFAULT 0, \
  PRIMARY KEY (id), \
  UNIQUE KEY(file_name) \
) ENGINE=InnoDB";

$mysql_command -BNe "SELECT ps_bug_url, GROUP_CONCAT(files_changed SEPARATOR ' ') AS files_changed \
                    from ar.percona_server_jira_commits GROUP BY ps_bug_url" | {
    while read line; do {
        ps_bug_url=`echo $line | awk '{print $1}'`;
        echo "# ps_bug_url: "$ps_bug_url;

        files_changed=`echo $line | awk '{$1=""}1'`;
        echo "# files_changed: "$files_changed;

        ps_bug_priority=`curl -s $ps_bug_url | grep -A1 priority-val | tail -n1 | sed -e 's/<.*\/>//g' | awk '{print $1}'`;
        echo "# bug_prio: "$ps_bug_priority;

        if [ -z ${ps_bug_priority} ]; then
            echo "# skipping due to empty prio...";
            continue
        fi

        case ${ps_bug_priority} in
            Low)
                echo "Low";
                ps_bug_severity=1;
                ;;
            Medium)
                echo "Medium";
                ps_bug_severity=2;
                ;;
            High)
                echo "High";
                ps_bug_severity=4;
                ;;
            Critical)
                echo "Critical";
                ps_bug_severity=8;
                ;;
            *)
                echo "No match for: "${ps_bug_priority};
                ps_bug_severity=0;
                ;;
        esac

        for file_changed in `echo $files_changed`; do {
            echo "# file_changed: "$file_changed;
            $mysql_command -e "INSERT INTO ar.percona_server_file_severity (file_name, severity) VALUES ('${file_changed}', $ps_bug_severity) \
                                ON DUPLICATE KEY UPDATE severity=severity+$ps_bug_severity;"
        } done;

        echo;
    } done;
} > /tmp/ar_severities.out 2>&1


