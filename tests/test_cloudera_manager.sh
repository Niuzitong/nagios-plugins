#!/usr/bin/env bash
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-05-06 12:12:15 +0100 (Fri, 06 May 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#
#  https://www.linkedin.com/in/harisekhon
#

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

srcdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd "$srcdir/.."

. "$srcdir/utils.sh"

is_travis && exit 0

section "C l o u d e r a   M a n a g e r"

export QUICKSTART_CLUSTER="Cloudera QuickStart"
export CM_PORT="${CM_PORT:-7180}"
export CM_USER="${CM_USER:-admin}"
export CM_PASSWORD="${CM_USER:-admin}"
export CM_CLUSTER="${CM_CLUSTER:-$QUICKSTART_CLUSTER}"
export CM_VERSION="${CM_VERSION:-.*}"
PROTOCOL="http"
if [ -n "${CM_SSL:-}" ]; then
    PROTOCOL="https"
    # TODO: SSL env var support in plugins and set here
fi

trap_debug_env cm

echo "checking connection refused tests first:"
echo
run_conn_refused $perl -T check_cloudera_manager_version.pl -e "$CM_VERSION"
hr
run_conn_refused $perl -T check_cloudera_manager.pl --api-ping
hr
run_conn_refused $perl -T check_cloudera_manager_config_stale.pl --list-roles -S hdfs
hr
run_conn_refused $perl -T check_cloudera_manager_cluster_version.pl
hr
run_conn_refused $perl -T check_cloudera_manager_config_stale.pl -S "hdfs"
hr
run_conn_refused $perl -T check_cloudera_manager_config_validation.pl -S "hdfs"
hr
run_conn_refused $perl -T check_cloudera_manager_health.pl -S "hdfs"
hr
run_conn_refused $perl -T check_cloudera_manager_license.pl
hr
run_conn_refused $perl -T check_cloudera_manager_metrics.pl -S "hdfs" -a
hr
run_conn_refused $perl -T check_cloudera_manager_status.pl -S "hdfs"
hr

echo

if [ -z "${CM_HOST:-}" ]; then
    echo "WARNING: \$CM_HOST not set, skipping real Cloudera Manager checks"
else
    if ! when_ports_available 5 "$CM_HOST" "$CM_PORT"; then
        echo "WARNING: Cloudera Manager host $CM_HOST:$CM_PORT not up, skipping Cloudera Manager checks"
        echo
        echo
        exit 0
    fi

    if when_url_content 5 "$PROTOCOL://$CM_HOST:$CM_PORT/cmf/login" Cloudera; then
        echo "WARNING: Cloudera Manager host $CM_HOST:$CM_PORT did not contain Cloudera in html, may be some other service bound to the port, skipping..."
        echo
        echo
        exit 0
    fi

    # QuickStart VM often has some broken stuff, we're testing the code works, not the cluster
    [ "$CM_CLUSTER" = "$QUICKSTART_CLUSTER" ] && set +e

    hr
    run $perl -T check_cloudera_manager_version.pl -e "$CM_VERSION"
    hr
    run $perl -T check_cloudera_manager.pl --api-ping
    hr
    run_fail 3 $perl -T check_cloudera_manager.pl --list-clusters
    hr
    run_fail 3 $perl -T check_cloudera_manager.pl --list-users
    hr
    run_fail 3 $perl -T check_cloudera_manager.pl --list-hosts
    hr
    run_fail 3 $perl -T check_cloudera_manager.pl --list-services
    hr
    run_fail 3 $perl -T check_cloudera_manager_config_stale.pl --list-roles -S hdfs
    hr
    run $perl -T check_cloudera_manager_cluster_version.pl
    hr
    run_fail 2 $perl -T check_cloudera_manager_cluster_version.pl --expected 'fail-version'
    hr
    echo

    # ============================================================================ #
    echo

    # messes up geting these variables right which impacts the runs of the plugins further down
    if [ -n "${DEBUG:-}" ]; then
        DEBUG2="$DEBUG"
        export DEBUG=""
    fi

    set +o pipefail

    services="$(./check_cloudera_manager_config_stale.pl --list-services | tail -n +3)"

    set -o pipefail

    echo "Services:

    $services
    "

    service="$(bash-tools/random_select.sh "$services")"

    echo "Selected service: $service"

    if [ -n "${DEBUG2:-}" ]; then
        export DEBUG="$DEBUG2"
    fi

    # ============================================================================ #

    hr
    run $perl -T check_cloudera_manager_config_stale.pl -S "$service"
    hr
    run $perl -T check_cloudera_manager_config_validation.pl -S "$service"
    hr
    run $perl -T check_cloudera_manager_health.pl -S "$service"
    hr
    run $perl -T check_cloudera_manager_license.pl
    hr
    run $perl -T check_cloudera_manager_metrics.pl -S "$service" -a
    hr
    run $perl -T check_cloudera_manager_status.pl -S "$service"
    hr
fi
echo
echo "Completed $run_count Cloudera Manager tests"
echo
echo "All Cloudera Manager tests passed successfully"
untrap
echo
echo
