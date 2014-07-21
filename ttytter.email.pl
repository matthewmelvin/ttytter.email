
use Sys::Hostname;
use MIME::Lite;
use MIME::Base64;
use Digest::MD5 qw(md5_hex);
use Date::Manip;
use HTML::Entities;
# use LWP::UserAgent;
use WWW::Mechanize;
use Data::Dumper;
use URI::Escape;
use Encode;
use JSON;


$UA = WWW::Mechanize->new();
$UA->timeout(10);

$SENDTO = 'Example User <user@example.com>';

$MSGIDS = "$ENV{'HOME'}/.ttytter.thrdids";
%MSGIDS = ();

if (open(F, "<$MSGIDS")) {
	while (<F>) {
		next unless (/(\d+) (\d+)/);
		$MSGIDS{$1} = $2;
	}
	close(F);
}


$VER = do {
        my @r = (q$Revision: 1.32 $ =~ /\d+/g);
        sprintf "%d."."%02d", @r
};

print $stdout "" . scalar(keys %MSGIDS) . " \"Message-Id\" / \"References\" pairs loaded.\n" if ( -t $stdout );

sub imgurl($) {
	my($url) = $_[0];
	my($html, $cid);

	$cid = md5_hex($url);

	$CIDS{$cid}->{'url'} = $url;

	$url =~ s/(twimg.com\/.*)$/$1:large/;

	$html = "\n<br><a href=\"$url\"><img src=\"cid:$cid\"></a><br>\n";

	return($html);
}

sub bingtrans($$) {
	my($orig) = $_[0];
	my($lang) = $_[1];
	my($json, $text);

	print $stdout "translating from $lang: $orig\n" if ( -t $stdout );

	eval { $res = $UA->post("https://datamarket.accesscontrol.windows.net/v2/OAuth2-13",
		[
			'client_id' => "ttytter_email_pl",
        		'client_secret' => "bmVlZCBhIHJlYWwga2V5IGZvciB0cmFuc2xhdGlvbiBhcGk=",
			'scope' => "http://api.microsofttranslator.com",
			'grant_type' => "client_credentials"
		]
	); };
	return($orig) unless ($@ eq "");

	eval { $json = from_json($res->content) };
	return($orig) unless ($@ eq "");

	$text = uri_escape(encode("UTF-8", $orig));

	eval { $res = $UA->get("https://api.microsofttranslator.com/V2/Http.svc/Translate?text=$text" .
				"&to=en" .
				"&from=$lang",
			'Authorization' => "Bearer " . $json->{'access_token'}
	); };
	return($orig) unless ($@ eq "");

	$text = $res->content;

	return($orig) unless ($text =~ s/^<string[^>]*>//);
	return($orig) unless ($text =~ s/<\/string[^>]*>$//);

	$text = decode_entities($text);

	print $stdout "translated to en: $text\n" if ( -t $stdout );

	return($text);
}

sub unredir($) {
	my($url) = $_[0];
	my($res);
	my($cnt) = 1;
	# print $stdout "un-redirecting $url ...\n" if ( -t $stdout );

	while ($cnt <= 3) {
		# if the domain name is long(ish) it's probably not a url shortener
		last if ($url =~ m!://[^/]{12,}!);  # youtube's shortner is 8 chars

		eval { $res = $UA->get($url); };
		last unless ($@ eq "");

		last unless (defined($res->request->uri));
		last if ($url eq $res->request->uri);

		$url = $res->request->uri;
		# print $stdout "un-redirected url $cnt: $url\n" if ( -t $stdout );
		$cnt++;
	}

	return(sprintf('<a href="%s">%s</a>', $url, $url));
}

$handle = sub {
        my $ref = shift;
	my($host) = hostname();
	my($name) = &descape($ref->{'user'}->{'screen_name'});
	my($text) = &descape($ref->{'text'});
	my($repl, $msgid, $thrdid);
	my($subj) = "$name: $text";
	my($mesg, $date, $url, %seen, $body, $cid, $img, $tags, $src);

	# print Dumper($ref);

	$subj =~ s/[^\012\040-\176]/?/g;

	$msgid = &descape($ref->{'id_str'});

	if ($MSGIDS{$msgid}) {
		$date = UnixDate($ref->{'created_at'}, "%H:%M:%S");
		print $stdout "$date: $subj (SEEN)\n" if ( -t $stdout );
		return 1;
	}

	if ($ref->{'retweeted_status'}) {
		if ($ref->{'retweeted_status'}->{'in_reply_to_status_id_str'}) {
			$thrdid = &descape($ref->{'retweeted_status'}->{'in_reply_to_status_id_str'});
			$repl = &descape($ref->{'retweeted_status'}->{'in_reply_to_screen_name'});
		} else {
			$thrdid = &descape($ref->{'retweeted_status'}->{'id_str'});
			$repl = &descape($ref->{'retweeted_status'}->{'user'}->{'screen_name'});
		}
	} else {
		if ($ref->{'in_reply_to_status_id_str'}) {
			$thrdid = &descape($ref->{'in_reply_to_status_id_str'});
			$repl = &descape($ref->{'in_reply_to_screen_name'});
		} else {
			$thrdid = undef;
			$repl = undef;
		}
	}

	if ($thrdid) {
		$thrdid = $MSGIDS{$thrdid} if ($MSGIDS{$thrdid});
	} else {
		$thrdid = $msgid;
	}
	$MSGIDS{$msgid} = $thrdid;

	# keep a record if each transformation
	$ref->{'tran'} = [];
	push(@{$ref->{'tran'}}, $text);


	# remove any horizontal tabs, or carriage returns
	push(@{$ref->{'tran'}}, "remove: HT CR");
	$text =~ s/\\[tr]/ /g;
	push(@{$ref->{'tran'}}, $text);

	# convert any line feeds to breaks
	push(@{$ref->{'tran'}}, "remove: LF");
	$text =~ s/\\n/<br>/g;
	push(@{$ref->{'tran'}}, $text);

	# translate the text if not in english
	if (($ref->{'lang'}) && ($ref->{'lang'} ne "en")) {
		push(@{$ref->{'tran'}}, "tanslate: " . $ref->{'lang'});
		$text = bingtrans($text, $ref->{'lang'});
		push(@{$ref->{'tran'}}, $text);
	}
	
	# replace text urls with href's.
	foreach (@{$ref->{'entities'}->{'urls'}}, @{$ref->{'retweeted_status'}->{'entities'}->{'urls'}}) {
		$url = &descape($_->{'expanded_url'});
		next if defined($seen{$url});
		$seen{$url} = 1;
		push(@{$ref->{'tran'}}, "unredir: $url");
		$text =~ s!(\Q$url\E)(\s|$)!sprintf("%s%s", unredir($1), $2)!segi;
		push(@{$ref->{'tran'}}, $text);
	}

	# replace img urls with inline images
	%CIDS = ();
	foreach (@{$ref->{'entities'}->{'media'}}, @{$ref->{'retweeted_status'}->{'entities'}->{'media'}}) {
		foreach $url (&descape($_->{'media_url'}), &descape($_->{'media_url_https'})) {
			next if defined($seen{$url});
			$seen{$url} = 1;
			# print $stdout "Searching for $url in $text ...\n" if ( -t $stdout );
			push(@{$ref->{'tran'}}, "imgurl: $url");
			$text =~ s!(\Q$url\E)!imgurl($1)!segi;
			push(@{$ref->{'tran'}}, $text);
		}
	}


	# dereference and wrap up in href's any naked urls
	if (($text !~ /<a href=/) && ($text =~ m!https?://t\.co/[a-zA-Z0-9]*!)) {
		push(@{$ref->{'tran'}}, "naked urls: " . $ref->{'lang'});
		$text =~ s!(https?://t\.co/[a-zA-Z0-9]*)!unredir($1)!eg;
	}

	# turn any hashtags into links to real time search	
	push(@{$ref->{'tran'}}, "hashtags...");
	$text =~ s/(^|\s+)#([^\s<]+)/$1<a href="https:\/\/twitter.com\/search\/realtime\/$2">#$2<\/a>/g;
	push(@{$ref->{'tran'}}, $text);

	# replace any @ mentions into links to the user's profile
	push(@{$ref->{'tran'}}, "users...");
	$text =~ s/(^|\s+|\.|")\@([a-zA-Z0-9_]{1,15})/$1<a href="https:\/\/twitter.com\/$2">\@$2<\/a>/g;
	push(@{$ref->{'tran'}}, $text);

	# replace <'s and >'s that aren't part of a's or br's
	push(@{$ref->{'tran'}}, "angle brackets...");
	$text =~ s#<(?!(a href=|/a>|br>|img))#&lt;#sg;
	$text =~ s#(?<!(."|/a|br))>#&gt;#sg;
	push(@{$ref->{'tran'}}, $text);

	$body = "<html><body>\n";
	$body .= "<a href=\"https://twitter.com/$name\">$name</a>: $text\n";

	$body .= "<p>\n";

	$body .= "URL: <a href=\"https://twitter.com/$name/statuses/$msgid\">https://twitter.com/$name/statuses/$msgid</a>\n";
	if ($msgid ne $thrdid) {
		$body .= "<br>REF: <a href=\"https://twitter.com/$repl/statuses/$thrdid\">https://twitter.com/$repl/statuses/$thrdid</a>\n";
	}

	$body .= "<p>\n";

	$body .= "<!-- \n\n";
        $body .= "base64 --decode --ignore-garbage << _EOF_\n";
        $body .= encode_base64(Dumper($ref));
        $body .= "_EOF_\n";
        $body .= "\n -->\n"; 

	$body .= "</body></html>\n";

	$tags = "{ ";
	foreach (keys %{$ref->{'tag'}}) {
        	if ($tags =~ /=>/ ) {
			$tags .= ", "
		}
		$tags .= "$_ => " . &descape($ref->{'tag'}->{$_});
	}
	$tags .= " }";

	$src = &descape($ref->{'source'});
	
	$mesg = MIME::Lite->new(
		'Subject' => $subj,
		'Type' => 'multipart/related',
		'From:' => $SENDTO,
		'To:' => $SENDTO,
		'Message-Id' => "<ttytter.$msgid\@$host>",
		'References' => "<ttytter.$thrdid\@$host>",
		'X-Psuedo-Feed-Url' => 'http://twitter.com',
		'X-TTYtter-Email' => $VER,
		'X-TTYtter-Tags' => $tags,
		'X-TTYtter-Source' => $src
	);

	$mesg->attach(
		'Type' => "text/html",
		'Data' => $body,
		'Encoding' => '8bit'
	);


	foreach $cid (keys %CIDS) {
		$img = $CIDS{$cid}->{'url'};

		# print $stdout "Getting img: $img\n" if ( -t $stdout );
		eval { $UA->get($img); };
		unless ($@ eq "") {
			$@ =~ s/\n.*$//s;
			print $stdout "Failed img: $@\n" if ( -t $stdout );
			next;
		}

		unless ($UA->success()) {
			print $stdout "Failed img: $img\n" if ( -t $stdout );
			next;
		}

		$CIDS{$cid}->{'img'} = $UA->content();
		$CIDS{$cid}->{'type'} = $UA->ct();

		next unless (defined $CIDS{$cid}->{'type'} =~ /image/);

		$mesg->attach(
			'Type' => $CIDS{$cid}->{'type'},
			'Id' => $cid,
			'Data' => $CIDS{$cid}->{'img'},
			'X-Comment' => $CIDS{$cid}->{'url'}
		);
	}     	

	$mesg->send();

	$date = UnixDate($ref->{'created_at'}, "%H:%M:%S");
	print $stdout "$date: $subj\n" if ( -t $stdout );
};

$conclude = sub {
	my($idx) = 0;
	if (open(F, ">$MSGIDS")) {
		foreach (sort { $b <=> $a } keys %MSGIDS) {
			print F "$_ $MSGIDS{$_}\n";
			last if ($idx++ > 10000);
		}
		close(F);
	}

	&defaultconclude;
};
