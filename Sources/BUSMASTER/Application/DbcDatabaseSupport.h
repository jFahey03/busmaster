/*
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/**
 * \file      DbcDatabaseSupport.h
 * \brief     Helpers to associate CANdb++ (*.dbc) files directly
 *
 * BUSMASTER historically required a *.dbc file to be run through the Format
 * Converter to produce a *.dbf before it could be associated with a channel.
 * These helpers let a *.dbc be handed to the database loader as-is. The
 * database manager is asked to parse it natively first; only when it refuses
 * the format is the bundled DBC to DBF converter used to produce a shadow
 * *.dbf in the user data folder.
 */

#pragma once

#include <string>

/**
 * Returns true when strFilePath carries the CANdb++ (*.dbc) extension. The
 * comparison is case insensitive.
 */
bool bIsDbcDatabaseFile(const std::string& strFilePath);

/**
 * Converts strDbcPath into a *.dbf held in the BUSMASTER user data folder and
 * returns its full path in strDbfPath.
 *
 * The shadow file is reused while it is newer than the *.dbc it came from, so
 * re-opening a configuration does not pay for a conversion every time. On
 * failure strError carries the converter's diagnostics and strDbfPath is left
 * untouched.
 */
bool bConvertDbcToShadowDbf(const std::string& strDbcPath,
                            std::string& strDbfPath,
                            std::string& strError);
