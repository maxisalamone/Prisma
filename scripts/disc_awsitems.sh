#!/bin/bash

AWS_METRICPROFILE="$1"
AWS_METRICTYPE="$2"
AWS_HOST="$3"
#AWS_METRIC="$4"

if [ ! "$#" -ge "3" ]; then
        echo -e "\nYou did not supply enough arguments. \nUsage: $0 <AWS_PROFILE> <AWS_METRICTYPE> <HOST> \n \nExample:\n $0 UsrAWS_062_BP_PROD RDS rds-praw006 \n\n $0 UsrAWS_008_Acquiring_Prod ApplicationELB prod-alb-smartlapos-web-giveaway \n\n $0 secret_id_UsrAWS_132_IP_PROD ContainerInsights vip-release-eks-cluster " && exit "3"
fi

echo "Estoy ejecutando $(date +%F) $AWS_METRICPROFILE - $AWS_METRICTYPE $AWS_HOST " >> /usr/lib/nagios/plugins/aws_integration/eventscripts/debug

#CAMPO="fullcommand"
NAGIOSPATH="/usr/lib/nagios/plugins"
#DEBUG=2
DBGF=$(basename $0)
REDISSEARCH=0

SCRIPTDIR="/usr/lib/nagios/plugins/aws_integration"
cd ${SCRIPTDIR}

if [ -z "${SCRIPTDIR}" ]
then
        cd $(dirname $0)/..
        SCRIPTDIR=$(pwd)
fi

DISCOVERY="REDIS"

. /usr/lib/nagios/plugins/nagioscfg/conf/settings.sh
. /usr/lib/nagios/plugins/nagioscfg/eventscripts/zagios_functions.sh

if [ -f ${SCRIPTDIR}/conf/aws_settings.sh ]
then
	. ${SCRIPTDIR}/conf/aws_settings.sh
fi

#. ${SCRIPTDIR}/scripts/SEC_functions.sh

DBGFL="${SCRIPTDIR}/logs/$(date +%F)_${DBGF}_${AMB}:${LABELN}.log"

function search_in_csv_file () {


	if [ -f "${SCRIPTDIR}/dbs/awsitems.csv" ]
	then
		REDISRESULTADO=$( grep "${AWS_HOST}:${AWS_METRICTYPE}:${AWS_METRIC}|" ${SCRIPTDIR}/dbs/awsitems.csv | cut -d'|' -f2 )

		if [ -z "${REDISRESULTADO}" ]
		then
			REDISRESULTADO=$( grep "aws-default:${AWS_METRICTYPE}:${AWS_METRIC}|" ${SCRIPTDIR}/dbs/awsitems.csv | cut -d'|' -f2 )

			if [ -z "${REDISRESULTADO}" ]
			then
				REDISRESULTADO=""
				return 0
			else
				if [ ! -s "${SCRIPTDIR}/dbs/csv/${AWS_METRICPROFILE}.${AWS_METRICTYPE}.metrics.csv" ]
				then
					REDISRESULTADO=""
					return 0
				fi

				DIMTMP=$( grep "${GREPPATTERN}" ${SCRIPTDIR}/dbs/csv/${AWS_METRICPROFILE}.${AWS_METRICTYPE}.metrics.csv )
				DIMEXIT=$?
				#echo $?	
				if [ $DIMEXIT -eq 0 ]
				then
					DIMARRAY=(${DIMTMP//;/ })
					INI=2
					JSONARRAY=0
					DIMENSIONS=""
					NBRELMDIMARRAY=${#DIMARRAY[@]}
					NBRDIM=$(( NBRELMDIMARRAY - 2 ))
					NMDIMINI=2
					VALDIMINI=$(( (NBRDIM / 2) + 2 ))

					while [ $NMDIMINI -lt ${NBRELMDIMARRAY} ]
					do 
				 		NM="${DIMARRAY[$NMDIMINI]}"
				 		((NMDIMINI+=2))
					 	VAL="${DIMARRAY[$VALDIMINI]}"
				 		((VALDIMINI+=2))
				 		DIMENSIONS="${DIMENSIONS}Name=${NM},Value=${VAL} "
					done
				else
					CALCULATEDAWSITEM=$(grep "${AWS_HOST}:${AWS_METRICTYPE}:${AWS_METRIC}" ${SCRIPTDIR}/dbs/Thresholds.csv | cut -d'|' -f3)

					if [ -z "${CALCULATEDAWSITEM}"]
					then
						CALCULATEDAWSITEM=$(grep "aws-default:${AWS_METRICTYPE}:${AWS_METRIC}" ${SCRIPTDIR}/dbs/Thresholds.csv | cut -d'|' -f3)
					fi	

					if [ "${CALCULATEDAWSITEM}" == "Calculated" ]
					then
				 		DIMENSIONS="Name=NA,Value=NA"
					else
						REDISRESULTADO=""
						return 0
					fi
				fi

				if [ -z "$DIMENSIONS" ]
				then
					#REDISRESULTADO="{\"data\":[]}"
					REDISRESULTADO=""
					return 0
				else
					DIMENSIONS="{ \"{#DIMENSIONS}\": \"${DIMENSIONS}\", \"{#AWSMETRICTYPE}\": \"${AWS_METRICTYPE}\" }"	
					#echo "${DIMENSIONS}"

					NAG_SGS=$( get_nagiossg ${AWS_HOST} ${AWS_METRIC} )

					if [ -z "${NAG_SGS}" ]
					then
						NAG_SGS=$( get_nagiossg aws-default_${AWS_METRICTYPE} ${AWS_METRIC} )

						if [ -z "${NAG_SGS}" ]
						then
							NAG_SGS="NA"
						fi
					fi

					ZBX_DTAGS=$( get_defaulttags ${AWS_HOST} ${AWS_METRIC} )
					DEFTAGS_ARR=(${ZBX_DTAGS})

					if [ "${DEFTAGS_ARR[0]}" == "NIL" ]
					then
						ZBX_DTAGS=$( get_defaulttags aws-default_${AWS_METRICTYPE} ${AWS_METRIC} )
						DEFTAGS_ARR=(${ZBX_DTAGS})
					fi

					if [ -z "${ZBX_DTAGS}" ]
					then
						ZBX_DTAGS="NIL NIL NOPRTV"
					fi

					NAG_SGS="${NAG_SGS} ${ZBX_DTAGS}"

					ITEM=${ITEM//\\/\\\\}

					NAG_SGS=${NAG_SGS// /] [}
					NAG_SGS="[${NAG_SGS}]"

					ZBXGROUPTAGS="{\"{#NAGIOSSGS}\":\"${NAG_SGS}\",\"{#ZBX_RSPNSBL}\":\"${DEFTAGS_ARR[0]}\",\"{#ZBX_SRVC}\":\"${DEFTAGS_ARR[1]}\",\"{#ZBX_OPRTV}\":\"${DEFTAGS_ARR[2]}\"}"

					# Separado usando archivos temporales y la opcion slurpfile para el caso de kafka ya que la lista de argumentos
					# es demasiado larga, de manera de no alterar otros flujos
					if [ "$AWS_METRICTYPE" == "Kafka" ]; then
							echo "$DIMENSIONS" > /tmp/dimensions.json
							echo "$ZBXGROUPTAGS" > /tmp/zbxgrouptags.json
							REDISRESULTADO=$(jq --slurpfile dimensions /tmp/dimensions.json '. |= . + $dimensions[0]' <<< "$REDISRESULTADO")
							REDISRESULTADO=$(jq --slurpfile zbxgrouptags /tmp/zbxgrouptags.json '. |= . + $zbxgrouptags[0]' <<< "$REDISRESULTADO")
							rm /tmp/dimensions.json /tmp/zbxgrouptags.json
					else
							REDISRESULTADO=$( echo "$REDISRESULTADO" | jq ". |= . + ${DIMENSIONS}")
							REDISRESULTADO=$( echo "$REDISRESULTADO" | jq ". |= . + ${ZBXGROUPTAGS}")
					fi
					if [ ${COMMAINI} -eq 1 ]
					then
						COMMAINI=0
					else
						REDISRESULTADO=",${REDISRESULTADO}"
					fi
				fi
			fi
		fi
	else
		REDISRESULTADO=""
	fi
}

function disc_awsitems () {

	#local AWS_HOST="$1"
	#local AWS_METRIC="$2"
	#local CAMPO="$3"
	if [ $REDISSEARCH -eq 1 ]
	then
		REDISMSG="HGET ${AMB}:${LABELN}:ITEMS ${AWS_HOST}:${AWS_METRIC}"
		REDISRESULTADO=$( { ${REDIS_COMMAND} ${REDISMSG} ; } 2>&1 )
		REDISEXITSTATUS=$?
		

		if [ $REDISEXITSTATUS -ne 0 ]
		then
			DISCOVERY="CSV"
			search_in_csv_file
		else
			if [ -z "${REDISRESULTADO}" ]
			then
				REDISRESULTADO=""
			fi
		fi

	else
		DISCOVERY="CSV"
		REDISSEARCH=1
		search_in_csv_file
		REDISSEARCH=0
	fi

	if [ $DEBUG -eq 2 ]
	then
		echo "REDISMSG: ${REDISMSG}" >> ${DBGFL}
		echo "REDISEXITSTATUS: ${REDISEXITSTATUS}" >> ${DBGFL}
		echo "DISCOVERY: ${DISCOVERY}" >> ${DBGFL}
		echo "REDISRESULTADO: ${REDISRESULTADO}" >> ${DBGFL}
	fi

	if [ ! -z "${REDISRESULTADO}" ]
	then
		echo "${REDISRESULTADO}"
	fi
	return ${REDISEXITSTATUS}

}

AWSITEMLIST=$(grep "${AWS_HOST}:${AWS_METRICTYPE}" ${SCRIPTDIR}/dbs/Thresholds.csv | cut -d'|' -f1 | cut -d':' -f3)

if [ -z "${AWSITEMLIST}" ]
then
	AWSITEMLIST=$(grep "aws-default:${AWS_METRICTYPE}" ${SCRIPTDIR}/dbs/Thresholds.csv | cut -d'|' -f1 | cut -d':' -f3)
fi

COMMAINI=1

echo "{\"data\":["	
for AWSITEM in ${AWSITEMLIST}
do
	AWS_METRIC=${AWSITEM}
	case ${AWS_METRICTYPE} in
		RDS|DocDB|ES)
			GREPPATTERN="AWS\\/${AWS_METRICTYPE};${AWS_METRIC};.*;${AWS_HOST}.*"
		;;
		ApplicationELB)
			GREPPATTERN="AWS\\/${AWS_METRICTYPE};${AWS_METRIC};LoadBalancer;app\\/${AWS_HOST}\\/.*"
		;;
		ContainerInsights)
			GREPPATTERN="${AWS_METRICTYPE};${AWS_METRIC};ClusterName;${AWS_HOST}.*"
		;;
		ElastiCache)
			GREPPATTERN="AWS\\/${AWS_METRICTYPE};${AWS_METRIC};CacheClusterId;${AWS_HOST}.*"
		;;
	esac
	disc_awsitems
done
echo "]}"	
