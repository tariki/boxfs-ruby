# DESCRIPTION

FuSE file system for OpenBox.

## REQUIREMENTS

- Linux 2.6
- FuSE (http://fuse.sourceforge.org)
- Ruby 1.8
- boxrubylib (https://github.com/tariki/boxrubylib)

## INSTALL

Decompress archive and enter its top directory, then type:

	# ruby setup.rb
  
## USAGE

	# boxfs.rb dir account password
  
The account and password are your Box.net account and password. 
The boxfs.rb command mounts your Box.net account tree at the 
specified dir. 

## LICENSE

Copyright (c) 2008-2010 Tomohiko Ariki.
  
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
  
