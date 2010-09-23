
use Sys::Hostname;
use MIME::Lite;
use Date::Manip;
use HTML::Entities;

$handle = sub {
        my $ref = shift;
	my($host) = hostname();
	my($name) = &descape($ref->{'user'}->{'screen_name'});
	my($text) = &descape($ref->{'text'});
	my($msgid) = &descape($ref->{'id'});
	my($thrdid) = &descape($ref->{'in_reply_to_status_id'});
	my($subj) = "$name: $text";
	my($mesg, $date, $orig);

	$thrdid = $msgid unless ($thrdid);

	$orig = $text;
	$text =~ s/\\[ntr]/ /g;
	$text =~ s/(https?:\/\/[^\s\"]+)/<a href="$1">$1<\/a>/g;
	$text =~ s/(^|\s+)#(\S+)/$1<a href="http:\/\/search.twitter.com\/search?q=$2">#$2<\/a>/g;
	$text =~ s/(^|\s+)\@([a-zA-Z0-9_]{1,15})/$1<a href="http:\/\/twitter.com\/$2">\@$2<\/a>/g;

	$mesg = MIME::Lite->new(
		'Subject' => $subj,
		'Type' => 'text/html',
		'Date' => $ref->{'created_at'},
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
	# $mesg->print($stdout);

	$date = UnixDate($ref->{'created_at'}, "%H:%M:%S");
	print $stdout "$date: $subj\n";

	return 1;
};
