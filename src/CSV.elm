module Csv exposing (Csv, parse)

{-| A parser for transforming CSV strings into usable input.

This library does its best to support RFC 4180, however, many CSV inputs do not strictly follow the standard.  There are two major deviations assumed in this library.

1. The `\n` character may be used instead of `\r\n` for new-lines.
2. The trailing new-line may be omitted.

# Types
@docs Csv

# Functions
@docs parse
-}

import String
import Result
import Combine exposing (Parser, (<*), (*>), (<*>), (<$), ($>), (<$>), (<|>))
import Combine.Char exposing (char, noneOf)

{-| Represents a CSV document.  All CSV documents are have a header row, even if that row is empty.
-}
type alias Csv =
    { headers : List String
    , records : List (List String)
    }

{-| Parse a CSV string into it's constituent fields.
-}
parse : String -> Result (List String) Csv
parse =
    addTrailingCrlf >> Combine.parse file >> Result.mapError thrd >> Result.map thrd

{-| Gets the third element of a tuple.
-}
thrd : (a, b, c) -> c
thrd (_, _, c) =
    c

{-| Adds a trailing CRLF to a string if not present.
-}
addTrailingCrlf : String -> String
addTrailingCrlf str =
    if not (String.endsWith "\r\n" str || String.endsWith "\n" str)
        then
            str ++ "\r\n"
        else
            str

{-
   RFC 4180 grammar, for reference.

   file = [header CRLF] record *(CRLF record) [CRLF]

   header = name *(COMMA name)

   record = field *(COMMA field)

   name = field

   field = (escaped / non-escaped)

   escaped = DQUOTE *(TEXTDATA / COMMA / CR / LF / 2DQUOTE) DQUOTE

   non-escaped = *TEXTDATA

   COMMA = %x2C

   CR = %x0D ;as per section 6.1 of RFC 2234 [2]

   DQUOTE =  %x22 ;as per section 6.1 of RFC 2234 [2]

   LF = %x0A ;as per section 6.1 of RFC 2234 [2]

   CRLF = CR LF ;as per section 6.1 of RFC 2234 [2]

   TEXTDATA =  %x20-21 / %x23-2B / %x2D-7E -- printable characters minus quotes.
-}

comma : Parser s Char
comma =
    char ','

doubleQuote : Parser s Char
doubleQuote =
    char '"'

cr : Parser s Char
cr =
    char '\r'

lf : Parser s Char
lf =
    char '\n'

-- This should probably return \r\n, but I'm never going to actually use it.
crlf : Parser s ()
crlf =
    () <$ ((cr *> lf) <|> lf) -- Unix people don't do crlf


doubleDoubleQuote : Parser s Char
doubleDoubleQuote =
    (doubleQuote *> doubleQuote)

-- Grab all non-quote data.
textData : Parser s Char
textData =
    noneOf ['"', ',', '\n', '\r']

nonEscaped : Parser s String
nonEscaped =
    Combine.many textData |> Combine.map String.fromList

escaped : Parser s String
escaped =
    let
        innerChar =
            Combine.choice [ textData, comma, cr, lf, doubleDoubleQuote ]
        innerString =
            Combine.many innerChar |> Combine.map String.fromList
    in
        doubleQuote *> innerString <* doubleQuote

field : Parser s String
field =
    Combine.choice [ escaped, nonEscaped ]

name : Parser s String
name = field

header : Parser s (List String)
header =
    Combine.sepBy comma name

record : Parser s (List String)
record =
    Combine.sepBy comma field

file : Parser s Csv
file =
    Csv <$> header
        <* crlf
        <*> Combine.many (record <* crlf)
        <* Combine.end

