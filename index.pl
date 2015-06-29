#!/usr/bin/perl

=comment

filedrop - host a simple file upload form that notifies you when someone you've allowed uploads a file

=cut

package FILEDROP;

use strict;
use Mail::Sendmail;
use CGI qw(escapeHTML);

our ($q);

sub param { return scalar($q->param(@_)); }

sub http_header {
  return CGI::header(@_);
}

sub html_header {
  my $buf = 
'<!DOCTYPE html>
<html>
<head>
<title>upload</title>
<meta name="viewport" content="initial-scale=1.0, user-scalable=no">
<link rel="stylesheet" type="text/css" href="main.css">
</head>
<body>
';
  return $buf;
}
sub html_footer {
  my $buf = "
</body>
</html>";
  return $buf;
}

sub handler {
  local ($q);
  $q = new CGI();

  # check for required config
  return print_alert("Error: missing ENV UPLOAD_DIR") if $ENV{UPLOAD_DIR} eq '';
  return print_alert("Error: ENV UPLOAD_DIR: $ENV{UPLOAD_DIR} is not writable")
    unless -d $ENV{UPLOAD_DIR} && -w $ENV{UPLOAD_DIR};
  return print_alert("Error: missing ENV ALLOW_PASSCODE") if $ENV{ALLOW_PASSCODE} eq '';
  return print_alert("Error: invalid ENV EMAIL_NOTIFY") unless $ENV{EMAIL_NOTIFY} =~ /\w\@\w/;
  return print_alert("Error: invalid ENV EMAIL_FROM") unless $ENV{EMAIL_FROM} =~ /\w\@\w/;

  my $act = param('act');
  my $codeRef = __PACKAGE__->can('act_'.$act);

  if (! $codeRef) {
    if (param('file') eq '') {
      $codeRef = \&act_printform;
    } else {
      $codeRef = \&act_upload;
    }
  }
  
  eval {
   $codeRef->();
  };
  if ($@) {
    print_alert("Error: ".escapeHTML($@));
  }
  return undef;
}

sub print_alert {
  my $buf = "<div class=dialog>".join("\n", @_)."<p align=center><button type=button class=primary-btn onclick='history.back();'>ok</button></div>";
  print http_header(), html_header(), $buf, html_footer();
  return undef;
}

sub isValidPasscode {
  my ($p) = @_;
  for (split /\s*\,\s*/, $ENV{ALLOW_PASSCODE}) {
    return 1 if $_ eq $p;
  }
  return 0;
}

sub clean_filename {
  my ($fn) = @_;
  my $rv;
  if ($fn =~ /([^\/\\]+)$/) {
    $rv = $1;
    $rv =~ s/[^\.\w]//g;
  }
  return $rv;
}

sub file_size {
  my ($path) = @_;
  my (@stat) = stat $path;
  my $fileSize = $stat[7];
  my $unit = 'b';
  if ($fileSize > 0) {
    if ($fileSize > 1024) {
      $fileSize /= 1024;
      $unit = 'KB';
    }
    if ($fileSize > 1024) {
      $fileSize /= 1024;
      $unit = 'MB';
    }
    if ($fileSize > 1024) {
      $fileSize /= 1024;
      $unit = 'GB';
    }
    $fileSize =~ s/(\.\d\d).*/$1/;
  }
  return ($fileSize, $unit);
}

sub rfill {
  my ($v,$delimiter, $len) = @_;
  $len ||= 30;
  $delimiter ||= ' ';
 
  my $need = $len - length($v);
  for (1 .. $need) {
    $v .= $delimiter;
  }
  return $v;
}

sub act_upload {
  return print_alert("Invalid passcode") unless isValidPasscode(param('passcode'));
  return print_alert("Missing Email address") unless param('email') =~ /^[^\@]+\@[^\@]+$/;
  chdir $ENV{UPLOAD_DIR} or die "could not chdir $ENV{UPLOAD_DIR}; $!\n";

  my @buf;

  # load files
  my @fn = $q->param('file');
  my @fh = $q->upload('file'); 
  my $i = 0;
  my $l = scalar(@fn);
  while ($i < $l) {
    my $fn = clean_filename($fn[$i]);
    my $fh = $fh[$i];
    if ($fn ne '') {
      unlink $fn if -f $fn;
      open my $fh2, "> $fn" or die "could not write $fn; $!\n";
      while (<$fh>) {
        print $fh2 $_;
      }
      close $fh2;
      my ($fileSize, $unit) = file_size($fn);
      push @buf, rfill("$fn ", ".", 50)." $fileSize $unit" if $fileSize > 0;
    }

    $i++;
  }

  if (scalar(@buf) == 0) {
    return print_alert("No files uploaded.");
  }

  my $email = param('email');
  my $body = "$email has uploaded the following files:\n".join("\n", @buf);
  $body .= "\n\nmessage:\n".param('message') if param('message') ne '';

  my %opts = (
  );

  sendmail(
    to => $ENV{EMAIL_NOTIFY},
    cc => $email,
    'Reply-To' => $email,
    from => $ENV{EMAIL_FROM},
    subject => 'file upload receipt',
    body => $body
  ) or die $Mail::Sendmail::error;

  if ($ENV{HTTP_USER_AGENT} =~ /\bcurl\b/) {
    print http_header(-type => 'text/plain'), "files uploaded successfully\n".join("\n", @buf)."\n";
  } else {
    print_alert("<h1>files uploaded successfully</h1>\n<pre>\n".join("\n", @buf)."\n</pre>\n");
  }
}

sub act_cmdlineinstruct {
  print http_header( -type => 'text/plain'),
"Command Line Upload Instructions
===============================================

Run the following command in your console:

curl -F 'email=YOUR\@EMAIL.com' -F 'passcode=PASSCODEHERE' -F 'file=@/path/to/your/file' ".$q->url()."
";
  return undef;
}

my $TOTAL_FILE_INPUTS = 30;
sub act_printform {
  my $buf = '
<div class=dialog>
<h1>Secure File Drop</h1>

<p align=center><a href="?act=cmdlineinstruct">command line upload instructions</a>

<form method=post enctype="multipart/form-data" onsubmit="showuploadmsg(); return true;">
  <p>
  <label>email<br><input required placeholder="your.email@address.com" type=email name=email value="'.escapeHTML(param('email')).'"></label>
  <p>
  <label>passcode<br>
    <input required type=text name=passcode value="'.escapeHTML(param('passcode')).'">
  </label>
  <p>
  <label>message<br>
    <textarea name=message placeholder=optional>'.escapeHTML(param('message')).'</textarea>
  </label>
  <p>
  <fieldset>
    <legend>upload files</legend>
    <div style="overflow: auto; height: 200px;">';
  $buf .= "<input type=file name=file><br>\n" for 1 .. $TOTAL_FILE_INPUTS;
  $buf .= '
  </fieldset>

  <div id=uploadmsg>
    Please wait while your file(s) are being uploaded. Do not navigate away from this page during the upload process. You may open another web browser tab/window while you are waiting.
  </div>

  <div id=buttonbar>
    <input class=primary-btn type=submit name=act value=upload>
  </div>
</form>
</div>
<script>
function showuploadmsg(){
  document.getElementById("uploadmsg").style.display="block";
}
</script>';
  print CGI::header(), html_header(), $buf, html_footer();
}

handler() unless caller;

1;
