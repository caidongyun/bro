##! SQL injection attack detection in HTTP.

@load base/frameworks/notice
@load base/frameworks/measurement
@load base/protocols/http

module HTTP;

export {
	redef enum Notice::Type += {
		## Indicates that a host performing SQL injection attacks was detected.
		SQL_Injection_Attacker,
		## Indicates that a host was seen to have SQL injection attacks against
		## it.  This is tracked by IP address as opposed to hostname.
		SQL_Injection_Victim,
	};
	
	redef enum Tags += {
		## Indicator of a URI based SQL injection attack.
		URI_SQLI,
		## Indicator of client body based SQL injection attack.  This is 
		## typically the body content of a POST request. Not implemented yet.
		POST_SQLI,
		## Indicator of a cookie based SQL injection attack. Not implemented yet.
		COOKIE_SQLI,
	};
	
	## Defines the threshold that determines if an SQL injection attack
	## is ongoing based on the number of requests that appear to be SQL 
	## injection attacks.
	const sqli_requests_threshold = 50 &redef;
	
	## Interval at which to watch for the
	## :bro:id:`HTTP::sqli_requests_threshold` variable to be crossed.
	## At the end of each interval the counter is reset.
	const sqli_requests_interval = 5min &redef;

	## Collecting samples will add extra data to notice emails
	## by collecting some sample SQL injection url paths.  Disable
	## sample collection by setting this value to 0.
	const collect_SQLi_samples = 5 &redef;

	## Regular expression is used to match URI based SQL injections.
	const match_sql_injection_uri = 
		  /[\?&][^[:blank:]\x00-\x37\|]+?=[\-[:alnum:]%]+([[:blank:]\x00-\x37]|\/\*.*?\*\/)*['"]?([[:blank:]\x00-\x37]|\/\*.*?\*\/|\)?;)+.*?([hH][aA][vV][iI][nN][gG]|[uU][nN][iI][oO][nN]|[eE][xX][eE][cC]|[sS][eE][lL][eE][cC][tT]|[dD][eE][lL][eE][tT][eE]|[dD][rR][oO][pP]|[dD][eE][cC][lL][aA][rR][eE]|[cC][rR][eE][aA][tT][eE]|[iI][nN][sS][eE][rR][tT])([[:blank:]\x00-\x37]|\/\*.*?\*\/)+/
		| /[\?&][^[:blank:]\x00-\x37\|]+?=[\-0-9%]+([[:blank:]\x00-\x37]|\/\*.*?\*\/)*['"]?([[:blank:]\x00-\x37]|\/\*.*?\*\/|\)?;)+([xX]?[oO][rR]|[nN]?[aA][nN][dD])([[:blank:]\x00-\x37]|\/\*.*?\*\/)+['"]?(([^a-zA-Z&]+)?=|[eE][xX][iI][sS][tT][sS])/
		| /[\?&][^[:blank:]\x00-\x37]+?=[\-0-9%]*([[:blank:]\x00-\x37]|\/\*.*?\*\/)*['"]([[:blank:]\x00-\x37]|\/\*.*?\*\/)*(-|=|\+|\|\|)([[:blank:]\x00-\x37]|\/\*.*?\*\/)*([0-9]|\(?[cC][oO][nN][vV][eE][rR][tT]|[cC][aA][sS][tT])/
		| /[\?&][^[:blank:]\x00-\x37\|]+?=([[:blank:]\x00-\x37]|\/\*.*?\*\/)*['"]([[:blank:]\x00-\x37]|\/\*.*?\*\/|;)*([xX]?[oO][rR]|[nN]?[aA][nN][dD]|[hH][aA][vV][iI][nN][gG]|[uU][nN][iI][oO][nN]|[eE][xX][eE][cC]|[sS][eE][lL][eE][cC][tT]|[dD][eE][lL][eE][tT][eE]|[dD][rR][oO][pP]|[dD][eE][cC][lL][aA][rR][eE]|[cC][rR][eE][aA][tT][eE]|[rR][eE][gG][eE][xX][pP]|[iI][nN][sS][eE][rR][tT])([[:blank:]\x00-\x37]|\/\*.*?\*\/|[\[(])+[a-zA-Z&]{2,}/
		| /[\?&][^[:blank:]\x00-\x37]+?=[^\.]*?([cC][hH][aA][rR]|[aA][sS][cC][iI][iI]|[sS][uU][bB][sS][tT][rR][iI][nN][gG]|[tT][rR][uU][nN][cC][aA][tT][eE]|[vV][eE][rR][sS][iI][oO][nN]|[lL][eE][nN][gG][tT][hH])\(/
		| /\/\*![[:digit:]]{5}.*?\*\// &redef;
}

function format_sqli_samples(samples: vector of Measurement::DataPoint): string
	{
	local ret = "SQL Injection samples\n---------------------";
	for ( i in samples )
		ret += "\n" + samples[i]$str;
	return ret;
	}

event bro_init() &priority=3
	{
	# Add filters to the metrics so that the metrics framework knows how to 
	# determine when it looks like an actual attack and how to respond when
	# thresholds are crossed.
	local r1: Measurement::Reducer = [$stream="http.sqli.attacker", $apply=set(Measurement::SUM), $samples=collect_SQLi_samples];
	Measurement::create([$epoch=sqli_requests_interval,
	                     $reducers=set(r1),
	                     $threshold_val(key: Measurement::Key, result: Measurement::Result) =
	                     	{ 
	                     	return double_to_count(result["http.sqli.attacker"]$sum);
	                     	},
	                     $threshold=sqli_requests_threshold,
	                     $threshold_crossed(key: Measurement::Key, result: Measurement::Result) = 
	                     	{
	                     	local r = result["http.sqli.attacker"];
	                     	NOTICE([$note=SQL_Injection_Attacker,
	                     	        $msg="An SQL injection attacker was discovered!",
	                     	        $email_body_sections=vector(format_sqli_samples(Measurement::get_samples(r))),
	                     	        $src=key$host,
	                     	        $identifier=cat(key$host)]);
	                     	}]);

	local r2: Measurement::Reducer = [$stream="http.sqli.victim", $apply=set(Measurement::SUM), $samples=collect_SQLi_samples];
	Measurement::create([$epoch=sqli_requests_interval,
	                     $reducers=set(r2),
	                     $threshold_val(key: Measurement::Key, result: Measurement::Result) =
	                     	{ 
	                     	return double_to_count(result["http.sqli.victim"]$sum);
	                     	},
	                     $threshold=sqli_requests_threshold,
	                     $threshold_crossed(key: Measurement::Key, result: Measurement::Result) = 
	                     	{
	                     	local r = result["http.sqli.victim"];
	                     	NOTICE([$note=SQL_Injection_Victim,
	                     	        $msg="An SQL injection victim was discovered!",
	                     	        $email_body_sections=vector(format_sqli_samples(Measurement::get_samples(r))),
	                     	        $src=key$host,
	                     	        $identifier=cat(key$host)]);
	                     	}]);
	}

event http_request(c: connection, method: string, original_URI: string,
                   unescaped_URI: string, version: string) &priority=3
	{
	if ( match_sql_injection_uri in unescaped_URI )
		{
		add c$http$tags[URI_SQLI];
		
		Measurement::add_data("http.sqli.attacker", [$host=c$id$orig_h], [$str=original_URI]);
		Measurement::add_data("http.sqli.victim",   [$host=c$id$resp_h], [$str=original_URI]);
		}
	}
