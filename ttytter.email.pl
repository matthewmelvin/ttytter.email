
use Sys::Hostname;
use MIME::Lite;
use MIME::Base64;
use Date::Manip;
use HTML::Entities;
use LWP::UserAgent;
use Data::Dumper;

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
        my @r = (q$Revision: 1.13 $ =~ /\d+/g);
        sprintf "%d."."%02d", @r
};

print $stdout "" . scalar(keys %MSGIDS) . " \"Message-Id\" / \"References\" pairs loaded.\n" if ( -t $stdout );

sub unredir($) {
	my($url) = $_[0];
	my($res, $ua);
	my($cnt) = 1;
	print $stdout "un-redirecting $url ...\n" if ( -t $stdout );

	$ua = LWP::UserAgent->new('max_redirect' => 1);
	$ua->timeout(10);

	while ($cnt <= 3) {
		# if the domain name is long(ish) it's probably not a url shortener
		last if ($url =~ m!://[^/]{9,}!);
		$res = $ua->get($url);

		last unless (defined($res->request->uri));
		last if ($url eq $res->request->uri);

		$url = $res->request->uri;
		print $stdout "un-redirected url $cnt: $url\n" if ( -t $stdout );
		$cnt++;
	}

	return(sprintf('<a href="%s">%s</a>', $url, $url));
}

$handle = sub {
        my $ref = shift;
	my($host) = hostname();
	my($name) = &descape($ref->{'user'}->{'screen_name'});
	my($text) = &descape($ref->{'text'});
	my($msgid) = &descape($ref->{'id_str'});
	my($thrdid) = &descape($ref->{'in_reply_to_status_id_str'});
	my($subj) = "$name: $text";
	my($mesg, $date, $orig, $url, %seen, $body);

	# print Dumper($ref);

	if ($MSGIDS{$msgid}) {
		$date = UnixDate($ref->{'created_at'}, "%H:%M:%S");
		print $stdout "$date: $subj (SEEN)\n" if ( -t $stdout );
		return 1;
	}

	if ($thrdid) {
		$thrdid = $MSGIDS{$thrdid} if ($MSGIDS{$thrdid});
	} else {
		$thrdid = $msgid;
	}
	$MSGIDS{$msgid} = $thrdid;


	$orig = $text;
	$text =~ s/\\[ntr]/ /g;
	# $text =~ s!(https?://([-\w\.]+)+(:\d+)?(/([\w/_\.\~\-\#\!,]*(\?\S+)?)?)?)!<a href="$1">$1</a>!g;
	foreach (@{$ref->{'entities'}->{'urls'}}, @{$ref->{'retweeted_status'}->{'entities'}->{'urls'}}) {
		$url = &descape($_->{'expanded_url'});
		next if defined($seen{$url});
		$seen{$url} = 1;
		print $stdout "Searching for $url in $text ...\n" if ( -t $stdout );
		$text =~ s!(\Q$url\E)!unredir($1)!eg;
	}
	foreach (@{$ref->{'entities'}->{'media'}}, @{$ref->{'retweeted_status'}->{'entities'}->{'media'}}) {
		foreach $url (&descape($_->{'media_url'}), &descape($_->{'media_url_https'})) {
			next if defined($seen{$url});
			$seen{$url} = 1;
			print $stdout "Searching for $url in $text ...\n" if ( -t $stdout );
			$text =~ s!(\Q$url\E)!unredir($1)!eg;
		}
	}
	$text =~ s!(https?://t\.co/[a-zA-Z0-9]*)!unredir($1)!eg;
	$text =~ s/(^|\s+)#(\S+)/$1<a href="http:\/\/twitter.com\/search\/realtime\/$2">#$2<\/a>/g;
	$text =~ s/(^|\s+|\.|")\@([a-zA-Z0-9_]{1,15})/$1<a href="http:\/\/twitter.com\/$2">\@$2<\/a>/g;

	$body = "<html><body>\n";
	$body .= "<a href=\"http://twitter.com/$name\">$name</a>: $text</a>\n";
	$body .= "<p>\n";
	$body .= "URL: <a href=\"http://twitter.com/$name/statuses/$msgid\">http://twitter.com/$name/statuses/$msgid</a></p>\n";

	$body .= "<!-- \n\n";
        $body .= "base64 --decode --ignore-garbage << _EOF_\n";
        $body .= encode_base64(Dumper($ref));
        $body .= "_EOF_\n";
        $body .= "\n -->\n"; 

	$body .= "</body></html>\n";

	$mesg = MIME::Lite->new(
		'Subject' => $subj,
		'Type' => 'text/html',
		'To:' => 'user@example.com',
		'Message-Id' => "<ttytter.$msgid\@$host>",
		'References' => "<ttytter.$thrdid\@$host>",
		'X-Psuedo-Feed-Url' => 'http://twitter.com',
		'X-TTYtter-Email' => $VER,
		'Data' => $body
	);

	$mesg->send();

	$date = UnixDate($ref->{'created_at'}, "%H:%M:%S");
	print $stdout "$date: $subj\n" if ( -t $stdout );
};

$conclude = sub {
	my($idx) = 0;
	if (open(F, ">$MSGIDS")) {
		foreach (sort { $b <=> $a } keys %MSGIDS) {
			print F "$_ $MSGIDS{$_}\n";
			last if ($idx++ > 1000);
		}
		close(F);
	}

	&defaultconclude;
};
