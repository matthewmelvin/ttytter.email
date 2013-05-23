
use Sys::Hostname;
use MIME::Lite;
use Date::Manip;
use HTML::Entities;
use LWP::UserAgent;

$MSGIDS = "$ENV{'HOME'}/.ttytter.thrdids";
%MSGIDS = ();
if (open(F, "<$MSGIDS")) {
	while (<F>) {
		next unless (/(\d+) (\d+)/);
		$MSGIDS{$1} = $2;
	}
	close(F);
}
print $stdout "" . scalar(keys %MSGIDS) . " \"Message-Id\" / \"References\" pairs loaded.\n";

sub unredir($) {
	my($url) = $_[0];
	my($res, $ua);
	print $stdout "un-redirecting $url ...\n";

	$ua = LWP::UserAgent->new('max_redirect' => 1);
	$res = $ua->get($url);

	if (defined($res->request->uri)) {
		$url = $res->request->uri;
	}

	print $stdout "un-redirected url: $url\n";

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
	my($mesg, $date, $orig);

	if ($MSGIDS{$msgid}) {
		$date = UnixDate($ref->{'created_at'}, "%H:%M:%S");
		print $stdout "$date: $subj (SEEN)\n";
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
	# http://t.co/i7GwIev8 
	$text =~ s!(https?://t\.co/[a-zA-Z0-9]*)!unredir($1)!eg;
	$text =~ s/(^|\s+)#(\S+)/$1<a href="http:\/\/twitter.com\/search\/realtime\/$2">#$2<\/a>/g;
	$text =~ s/(^|\s+|\.|")\@([a-zA-Z0-9_]{1,15})/$1<a href="http:\/\/twitter.com\/$2">\@$2<\/a>/g;

	$mesg = MIME::Lite->new(
		'Subject' => $subj,
		'Type' => 'text/html',
		'To:' => 'user@example.com',
		'Message-Id' => "<ttytter.$msgid\@$host>",
		'References' => "<ttytter.$thrdid\@$host>",
		'X-Psuedo-Feed-Url' => 'http://twitter.com',
		'Data' => "<html><body>
<a href=\"http://twitter.com/$name\">$name</a>: $text</a>
<p>URL: <a href=\"http://twitter.com/$name/statuses/$msgid\">http://twitter.com/$name/statuses/$msgid</a></p>
</body></html>
"
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
