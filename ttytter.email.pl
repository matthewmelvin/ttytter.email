
use Sys::Hostname;
use MIME::Lite;
use MIME::Base64;
use Digest::MD5 qw(md5_hex);
use Date::Manip;
use HTML::Entities;
# use LWP::UserAgent;
use WWW::Mechanize;
use Data::Dumper;


$UA = WWW::Mechanize->new();
$UA->timeout(10);

$SENDTO = 'user@example.com';

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
        my @r = (q$Revision: 1.15 $ =~ /\d+/g);
        sprintf "%d."."%02d", @r
};

print $stdout "" . scalar(keys %MSGIDS) . " \"Message-Id\" / \"References\" pairs loaded.\n" if ( -t $stdout );

sub imgurl($) {
	my($url) = $_[0];
	my($html, $cid);

	$cid = md5_hex($url);

	$html = "\n<br><a href=\"$url\"><img src=\"cid:$cid\"></a><br>\n";

	$CIDS{$cid}->{'url'} = $url;

	return($html);
}

sub unredir($) {
	my($url) = $_[0];
	my($res);
	my($cnt) = 1;
	print $stdout "un-redirecting $url ...\n" if ( -t $stdout );

	while ($cnt <= 3) {
		# if the domain name is long(ish) it's probably not a url shortener
		last if ($url =~ m!://[^/]{9,}!);  # youtube's shortner is 8 chars
		$res = $UA->get($url);

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

	my($mesg, $date, $orig, $url, %seen, $body, $cid, $img, $tags);

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
	# $text =~ s!(https?://t\.co/[a-zA-Z0-9]*)!unredir($1)!eg;

	# replace text urls with href's.
	foreach (@{$ref->{'entities'}->{'urls'}}, @{$ref->{'retweeted_status'}->{'entities'}->{'urls'}}) {
		$url = &descape($_->{'expanded_url'});
		next if defined($seen{$url});
		$seen{$url} = 1;
		print $stdout "Searching for $url in $text ...\n" if ( -t $stdout );
		$text =~ s!(\Q$url\E)!unredir($1)!seg;
	}

	# replace img urls with inline images
	%CIDS = ();
	foreach (@{$ref->{'entities'}->{'media'}}, @{$ref->{'retweeted_status'}->{'entities'}->{'media'}}) {
		foreach $url (&descape($_->{'media_url'}), &descape($_->{'media_url_https'})) {
			next if defined($seen{$url});
			$seen{$url} = 1;
			print $stdout "Searching for $url in $text ...\n" if ( -t $stdout );
			$text =~ s!(\Q$url\E)!imgurl($1)!seg;
		}
	}

	# turn any hashtags into links to real time search	
	$text =~ s/(^|\s+)#(\S+)/$1<a href="http:\/\/twitter.com\/search\/realtime\/$2">#$2<\/a>/g;

	# replace any @ mentions into links to the user's profile
	$text =~ s/(^|\s+|\.|")\@([a-zA-Z0-9_]{1,15})/$1<a href="http:\/\/twitter.com\/$2">\@$2<\/a>/g;

	$body = "<html><body>\n";
	$body .= "<a href=\"http://twitter.com/$name\">$name</a>: $text\n";
	$body .= "<p>\n";
	$body .= "URL: <a href=\"http://twitter.com/$name/statuses/$msgid\">http://twitter.com/$name/statuses/$msgid</a></p>\n";

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
	
	$mesg = MIME::Lite->new(
		'Subject' => $subj,
		'Type' => 'multipart/related',
		'To:' => $SENDTO,
		'Message-Id' => "<ttytter.$msgid\@$host>",
		'References' => "<ttytter.$thrdid\@$host>",
		'X-Psuedo-Feed-Url' => 'http://twitter.com',
		'X-TTYtter-Email' => $VER,
		'X-TTYtter-Tags' => $tags
	);

	$mesg->attach(
		'Type' => "text/html",
		'Data' => $body
	);


	foreach $cid (keys %CIDS) {
		$img = $CIDS{$cid}->{'url'};

		print $stdout "Getting img: $img\n" if ( -t $stdout );
		$UA->get($img);
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
