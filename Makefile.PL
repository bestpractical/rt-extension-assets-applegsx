use inc::Module::Install;


RTx 'RT-Extension-Assets-AppleGSX';
all_from 'lib/RT/Extension/Assets/AppleGSX.pm';
readme_from 'lib/RT/Extension/Assets/AppleGSX.pm';
license  'gplv2';

sign;
WriteAll;
