package Netrap::Parse;

use strict;
use Scalar::Util 'blessed';

use Data::Dumper;

use Netrap::Socket;
use Netrap::Socket::Printer;

use Netrap::FlowManager;

use IO::Termios;

my $upload_dir = 'upload/';

sub socket_list {
    my $requestor = shift;
    my $object = shift;

    $object = {} unless ref($object) eq 'HASH';

    $object->{sockets} = [];

    for (values %Netrap::Socket::sockets) {
        push @{$object->{sockets}}, $_->describe();
    }

    return $object;
}

sub printer_resolvename {
    my $printername = shift;

    return grep {$_->{name} =~ m#\Q$printername\E#} values %Netrap::Socket::Printer::PrinterSockets;
}

sub search_printer {
    my $requestor = shift;
    my $object = shift;

    my @printers;

    if (scalar keys(%Netrap::Socket::Printer::PrinterSockets) == 1) {
#         printf "Only one printer, returning %s\n", Dumper ((values(%Netrap::Socket::Printer::PrinterSockets))[0]);
        return ((values(%Netrap::Socket::Printer::PrinterSockets))[0]);
    }

    for (@_) {
        my $item = $_;
        if (ref($item)) {
            if (blessed($item) && $item->isa('Netrap::Socket::Printer')) {
                push @printers, $item;
            }
        }
        else {
            push @printers, printer_resolvename $item;
        }
        if (@printers > 0) {
            last;
        }
    }
    if (@printers == 0) {
        if (!ref($object)) {
            $object = {"printer" => $object};
        }
        if ($object->{printer}) {
            if (ref($object->{printer})) {
                if (blessed($object->{printer}) && $object->{printer}->isa('Netrap::Socket::Printer')) {
                    push @printers, $object->{printer};
                }
            }
            else {
                push @printers, printer_resolvename $object->{printer};
            }
        }
    }
    if (@printers == 0) {
        if ($requestor->{printer}) {
            if (ref($requestor->{printer})) {
                if (blessed($requestor->{printer}) && $requestor->{printer}->isa('Netrap::Socket::Printer')) {
                    push @printers, $requestor->{printer};
                }
            }
            else {
                push @printers, printer_resolvename $requestor->{printer};
            }
        }
    }

    return @printers;
}

sub printer_add {
    my $requestor = shift;
    my $object = shift;

    my $device;
    my $port;
    my $baud;

    return {'status' => 'ok'} if defined $requestor->{remaining} && $requestor->{remaining} > 0;

    if (ref($object)) {
        $device = $object->{device};
        $port = $object->{port};
        $baud = $object->{baud};
    }
    elsif ($object =~ /^(\S+)\s+(\d+)$/) {
        $device = $1;
        my $num = $2;
        $object = {"device" => $device};
        if ($device =~ m#^/# || $device =~ m#^com\d+#) {
            $baud = $num;
            $object->{"baud"} = $baud;
        }
        else {
            $port = $num;
            $object->{"port"} = $port;
        }
    }
    if ($device && $port && $port =~ /^\d+$/) {
        printf "Connecting to TCP printer at %s:%d\n", $device, $port;
        my $sock = new IO::Socket::INET(PeerAddr => $device, PeerPort => $port, Proto => 'tcp', Blocking => 0) or return "error: $!";
        my $newprinter = new Netrap::Socket::Printer($sock);
        $newprinter->{name} = sprintf "TCP:%s:%d", $device, $port;
        $newprinter->{maxtoken} = 16;
        $newprinter->{tokens} = $newprinter->{maxtoken};
        printf "Printer %s Created\n", $newprinter->{name};
        return {"printer" => $newprinter->{name}};
    }
    elsif ($device && $baud && $baud =~ /^\d+$/) {
#         printf "Could not connect to %s %d\n", $device, $baud;
        printf "Connecting to Serial printer at %s @%d\n", $device, $baud;
        my $sock = IO::Termios->open($device) or return "error: $!";
        if ($sock) {
            $sock->setbaud($baud);
            $sock->setcsize(8);
            $sock->setparity("n");
            $sock->setstop(1);
            my $newprinter = new Netrap::Socket::Printer($sock);
            $newprinter->{name} = sprintf "SERIAL:%s @%d", $device, $baud;
            printf "Printer %s Created\n", $newprinter->{name};
            return {%{$object}, "printer" => $newprinter->{name}};
        }
        die Dumper \$sock;
    }
    else {
        return sprintf "Invalid printer specification: %s", $object;
    }
    return %{$object};
}

sub printer_list {
    my $requestor = shift;
    my $object = shift;

    $object = {} unless ref($object) eq 'HASH';

    $object->{printers} = [];

    for (keys %Netrap::Socket::Printer::PrinterSockets) {
        my $printer = $Netrap::Socket::Printer::PrinterSockets{$_};
        my $item = {'name'=>$printer->{name}};
        if ($printer->{file}) {
            $item->{file} = $printer->{file}->{filename};
            $item->{filepos} = $printer->{file}->tell();
            $item->{filesize} = $printer->{file}->length();
        }
        push @{$object->{printers}}, $item;
    }
    $object->{printercount} = @{$object->{printers}};
    return $object;
}

sub printer_load {
    my $requestor = shift;
    my $object = shift;

    return {'status' => 'ok'} if defined $requestor->{remaining} && $requestor->{remaining} > 0;


    my @printers = search_printer($requestor, $object);
    if (@printers > 1) {
        return {'status' => 'error', 'error' => 'Printer ambiguous'};
    }
    elsif (@printers == 0) {
        return {'status' => 'error', 'error' => 'Printer not found'};
    }

    my $printer = $printers[0];

    if (ref($object) ne 'HASH') {
        $object = {"file" => $object};
    }

#     printf "Looking for '%s'\n", $upload_dir . $object->{file};

    if (-f $upload_dir . $object->{file}) {
#         printf "Found!\n";
        my $file = new Netrap::Socket::File($upload_dir . $object->{file});
        if ($file) {
            $file->freeze(1);
            $printer->{FlowManager}->addFeeder($file);
            $object->{length} = $file->{length};
            $printer->{file} = $file;
            $file->addReceiver('Close', $printer, $printer->can('fileComplete'));
            $object->{printer} = $printer->{name};
            return {%{$object}, 'status' => 'success'};
        }
        else {
            $object->{error} = "Could not open file: $!";
        }
    }
    else {
        $object->{error} = "File Not Found";
    }
    return {%{$object}, 'status' => 'error'};
}

sub printer_start {
    my $requestor = shift;
    my $object = shift;

    return {'status' => 'ok'} if defined $requestor->{remaining} && $requestor->{remaining} > 0;

    my @printers = search_printer($requestor, $object);
    if (@printers > 1) {
        return {'status' => 'error', 'error' => 'Printer ambiguous'};
    }
    elsif (@printers == 0) {
        return {'status' => 'error', 'error' => 'Printer not found'};
    }

    my $printer = $printers[0];
    if ($printer->{file}) {
        my $file = $printer->{file};
        if ($file->tell() != 0) {
            return {'status' => 'error', 'error' => 'Already started. Try restart or resume'};
        }
        my $frozen = $file->freeze(0);
        return {'status' => 'success', 'length' => $file->length(), 'position' => $file->tell(), 'remaining' => $file->remaining(), 'frozen' => $frozen};
    }
}

sub printer_pause {
    my $requestor = shift;
    my $object = shift;

    my @printers = search_printer($requestor, $object);
    if (@printers > 1) {
        return {'status' => 'error', 'error' => 'Printer ambiguous'};
    }
    elsif (@printers == 0) {
        return {'status' => 'error', 'error' => 'Printer not found'};
    }

    my $printer = $printers[0];
    if ($printer->{file}) {
        my $file = $printer->{file};
        $file->freeze(1);
        return {'status' => 'success', 'length' => $file->length(), 'position' => $file->tell(), 'remaining' => $file->remaining()};
    }
}

sub printer_resume {
    my $requestor = shift;
    my $object = shift;

    my @printers = search_printer($requestor, $object);
    if (@printers > 1) {
        return {'status' => 'error', 'error' => 'Printer ambiguous'};
    }
    elsif (@printers == 0) {
        return {'status' => 'error', 'error' => 'Printer not found'};
    }

    my $printer = $printers[0];
    if ($printer->{file}) {
        my $file = $printer->{file};
        $file->freeze(0);
        return {'status' => 'success', 'length' => $file->length(), 'position' => $file->tell(), 'remaining' => $file->remaining()};
    }
}

sub printer_restart {
    my $requestor = shift;
    my $object = shift;

    my @printers = search_printer($requestor, $object);
    if (@printers > 1) {
        return {'status' => 'error', 'error' => 'Printer ambiguous'};
    }
    elsif (@printers == 0) {
        return {'status' => 'error', 'error' => 'Printer not found'};
    }

    my $printer = $printers[0];
    if ($printer->{file}) {
        my $file = $printer->{file};
        $file->seek(0);
        $file->freeze(0);
        return {'status' => 'success', 'length' => $file->length(), 'position' => $file->tell(), 'remaining' => $file->remaining()};
    }
}

sub printer_stop {
    my $requestor = shift;
    my $object = shift;
}

sub printer_query {
    my $requestor = shift;
    my $object = shift;

#     print Dumper \$object;

    my @matches = search_printer($requestor, $object);
    if (@matches == 1) {
        my $printer = $matches[0];
#         printf "Got Printer %s\n", Dumper $printer;
        if (ref($object) eq 'HASH' && $object->{"content-length"}) {
            $printer->{FlowManager}->resetData();
            $printer->{FlowManager}->maxData($object->{"content-length"});
#             printf "CONTENT LENGTH %d\n", $printer->{FlowManager}->maxData();
        }
        $printer->raw(0);
        $requestor->raw(0);
        $requestor->{uploading} = 1;
        $printer->{FlowManager}->addReceiver('Complete', $requestor, \&printer_query_complete);
        $printer->{FlowManager}->addFeeder($requestor);
        return {"status" => "ok", "FlowManager" => $printer->{FlowManager}, "SendHeader" => 1, "Content-Type" => "text/plain"};
    }
    return {"status" => "error", "error" => "Printer not found"};
}

sub printer_query_complete {
    my $requestor = shift;
    my $fm = shift;

#     printf "PRINTER_QUERY_COMPLETE\n";

    my $printer = $fm->{sinks}->{$fm->{sinkOrder}->[0]};
    $printer->addReceiver('Token', $requestor, \&printer_query_last_response);
    $fm->removeReceiver('Complete', $requestor, \&printer_query_complete);
}

sub printer_query_last_response {
    my $requestor = shift;
    my $printer = shift;

#     printf "PRINTER_QUERY_LAST_RESPONSE %s\n", $requestor->describe();

    $printer->removeReceiver('Token', $requestor, \&printer_query_last_response);
    $printer->{FlowManager}->removeFeeder($requestor);

    $requestor->flushrx();
    $requestor->close();
}

sub printer_select {
    my $requestor = shift;
    my $object = shift;

#     print "Looking for $printername\n";

    my @matches = search_printer($requestor, $object);
    if (@matches == 1) {
#         printf "requestor printer is %s\n", $requestor->{printer};
        $requestor->{printer}->{FlowManager}->removeFeeder($requestor) if $requestor->{printer};
        $requestor->{printer} = $matches[0];
        $requestor->{printer}->{FlowManager}->addFeeder($requestor);
#         printf "Found %s\n", $matches[0]->{name};
        return {"printer" => $matches[0]->{name} };
    }
    if (@matches > 1) {
#         print sprintf "error: %d names match requested string\n", scalar @matches;
        return sprintf "error: %d names match requested string", scalar @matches;
    }
#     print "No matches";
    return "No matches";
}

sub printer_dump {
    my $requestor = shift;
    my $object = shift;

    my @matches = search_printer($requestor, $object);
    if (@matches == 1) {
        my $printer = $matches[0];

        print Dumper $printer;
        return $printer;
    }

    return $requestor->{printer} or %Netrap::Socket::Printer::PrinterSockets;
}

sub printer_close {
    my $requestor = shift;
    my $object = shift;

    my @printers = search_printer($requestor, $object);
    if (@printers > 1) {
        return {'status' => 'error', 'error' => sprintf 'Printer name ambiguous: %d printers matched', scalar @printers};
    }
    if (@printers == 1) {
        my $printer = $printers[0];
        printf "Printer %s closing...\n", $printer->describe();
        $printer->close();
        return {'status' => 'ok', 'printer' => $printer->{name}};
    }
    return {'status' => 'error', 'error' => sprintf 'Printer not found'};
}

sub printer_poke {
    my $requestor = shift;
    my $object = shift;

    my @printers = search_printer($requestor, $object);
    if (@printers > 1) {
        return {'status' => 'error', 'error' => sprintf 'Printer name ambiguous: %d printers matched', scalar @printers};
    }
    if (@printers == 1) {
        my $printer = $printers[0];
        my $t = $printer->{tokens};
        my $mt = $printer->{maxtoken};
        if ($t < $mt) {
            $printer->poke();
        }
        return {'status' => 'ok', 'printer' => $printer->{name}, 'tokens' => $t, 'maxtoken' => $mt};
    }
    return {'status' => 'error', 'error' => sprintf 'Printer not found'};
}

sub file_load {
    my $requestor = shift;
    my $object = shift;

    if (ref($object) ne 'HASH') {
        $object = {"name" => $object};
    }
    if (-r $upload_dir . $object->{name}) {
        my $file = new Netrap::Socket::File($upload_dir . $object->{name});
        if ($file) {
            $object->{length} = $file->{length};
            $requestor->{file} = $file;
            return $object;
        }
        else {
            $object->{error} = "Could not open file: $!";
        }
    }
    else {
        $object->{error} = "File Not Found";
    }
    return {%{$object}, 'status' => 'error'};
}

sub file_list {
    my $requestor = shift;
    my $object = shift;

    opendir D, $upload_dir or die $!;
    my @l = readdir D;
    closedir D;

    my @r;

    for (@l) {
        if (!m#^\.\.?$#) {
            my $filename = $upload_dir.$_;
            my %f = ('name' => $_);
            $f{type} = 'directory' if -d $filename;
            $f{type} = 'file' if -f $filename;
            $f{size} = (stat(_))[7];
            push @r, \%f if $f{type};
        }
    }
    $object = {} unless $object && ref($object) eq 'HASH';
    return {%{$object}, 'files' => \@r};
}

sub file_upload {
    my $requestor = shift;
    my $object = shift;

    my $remaining;
    my $filename;

    if (!ref($object)) {
        if ($object =~ /^(.*?)\s+(\d+)$/) {
            $filename = $1;
            $remaining = $2;
        }
        else {
            $filename = $object;
        }
        $object = {'filename' => $filename};
    }
    else {
#         print Dumper $object;
        $filename = $object->{filename} if $object->{filename};
        $remaining = $object->{remaining} if $object->{remaining};
#         printf "GOT %d: %s\n", $remaining, $filename;
    }

    if (!defined $remaining && defined $requestor->{remaining}) {
        $remaining = $requestor->{remaining};
    }

    if (defined $remaining && $remaining =~ /^\d+$/ && $remaining > 0 && $filename =~ m#^[a-z][^/:]+\.[^/:]+$#i) {
        $requestor->{uploading} = $remaining;
        my $file = new Netrap::Socket::File($upload_dir . $filename, 'w');
        if ($file) {
#             print Dumper $requestor;
            $requestor->raw(1);
            $file->readmode(0);
            $file->writemode(1);
            $file->raw(1);
            my $fm = new Netrap::FlowManager();
            $fm->maxData($remaining);
            $fm->addFeeder($requestor);
            $fm->addSink($file);
#             $fm->addReceiver('Complete', $fm, \&file_upload_complete, $requestor, $file);
            $fm->addReceiver('Complete', $fm, sub { file_upload_complete($fm, $requestor, $file); });
            return {%{$object}, 'status' => 'ok', 'UploadFile' => $file, 'UploadManager' => $fm};
        }
    }
    else {
        return {%{$object}, 'status' => 'error', 'error' => "Can't determine length of upload"};
    }
}

sub file_upload_complete {
    my $fm = shift;
    my $requestor = shift;
    my $file = shift;

    delete $requestor->{uploading};

    printf "file_upload_complete '%s' '%s' '%s'\n", $fm, $requestor, $file;

    $fm->removeFeeder($requestor);

    $fm->removeSink($file);

    $file->close();
}

sub file_describe {
    my $requestor = shift;
    my $object = shift;
}

sub file_delete {
    my $requestor = shift;
    my $object = shift;
    return {%{$object}, 'status' => 'error', 'error' => 'bad filename'} if $object->{file} =~ /(\.\.\/|\/\.\.)/;
    unlink $upload_dir.$object->{file} if -r $upload_dir.$object->{file};
    return $object;
}

sub file_close {
    my $requestor = shift;
    my $object = shift;

    if ($requestor->{file}) {
        delete $requestor->{file};
    }

    return undef;
}

my %actions = (
    'socket' => {
        'list'     => \&socket_list,
    },
    'printer' => {
        'add'      => \&printer_add,
        'close'    => \&printer_close,
        'list'     => \&printer_list,
        'load'     => \&printer_load,
        'start'    => \&printer_start,
        'pause'    => \&printer_pause,
        'resume'   => \&printer_resume,
        'restart'  => \&printer_restart,
        'stop'     => \&printer_stop,
        'query'    => \&printer_query,
        'select'   => \&printer_select,
        'use'      => \&printer_select,
        'dump'     => \&printer_dump,
        'poke'     => \&printer_poke,
    },
    'file' => {
        'load'     => \&file_load,
        'list'     => \&file_list,
        'upload'   => \&file_upload,
        'describe' => \&file_describe,
        'delete'   => \&file_delete,
    },
);

sub targets {
    my $target = shift;
    if ($target) {
        return grep {/\Q$target\E/} keys %actions;
    }
    return keys %actions;
}

sub actions {
    my $target = shift or return undef;
    my $action = shift or return undef;

    return $actions{$target}->{$action} if $actions{$target} && $actions{$target}->{$action};
    return undef;
}

