{-# LANGUAGE NoImplicitPrelude #-}
-- | Utilities for dealing with YAML config files which contain relative file
-- paths.
module Data.Yaml.FilePath
    ( decodeFileRelative
    , lookupBase
    , lookupBaseMaybe
    , BaseDir
    , ParseYamlFile (..)
    , NonEmptyVector (..)
    ) where

import Control.Applicative ((<$>))
import Filesystem.Path.CurrentOS (FilePath, encodeString, directory, fromText, (</>))
import Data.Yaml (decodeFileEither, ParseException (AesonException), parseJSON)
import Prelude (($!), ($), Either (..), return, IO, (.), (>>=), Maybe (..), maybe, mapM, Ord, fail)
import Data.Aeson.Types ((.:), (.:?), Object, Parser, Value, parseEither)
import Data.Text (Text)
import qualified Data.Set as Set
import qualified Data.Vector as V

-- | The directory from which we're reading the config file.
newtype BaseDir = BaseDir FilePath

-- | Parse a config file, using the 'ParseYamlFile' typeclass.
decodeFileRelative :: ParseYamlFile a
                   => FilePath
                   -> IO (Either ParseException a)
decodeFileRelative fp = do
    evalue <- decodeFileEither $ encodeString fp
    return $! case evalue of
        Left e -> Left e
        Right value ->
            case parseEither (parseYamlFile basedir) value of
                Left s -> Left $! AesonException s
                Right x -> Right $! x
  where
    basedir = BaseDir $ directory fp

-- | A replacement for the @.:@ operator which will both parse a file path and
-- apply the relative file logic.
lookupBase :: ParseYamlFile a => BaseDir -> Object -> Text -> Parser a
lookupBase basedir o t = (o .: t) >>= parseYamlFile basedir

-- | A replacement for the @.:?@ operator which will both parse a file path and
-- apply the relative file logic.
lookupBaseMaybe :: ParseYamlFile a => BaseDir -> Object -> Text -> Parser (Maybe a)
lookupBaseMaybe basedir o t = (o .:? t) >>= maybe (return Nothing) ((Just <$>) . parseYamlFile basedir)

-- | A replacement for the standard @FromJSON@ typeclass which can handle relative filepaths.
class ParseYamlFile a where
    parseYamlFile :: BaseDir -> Value -> Parser a

instance ParseYamlFile FilePath where
    parseYamlFile (BaseDir dir) o = ((dir </>) . fromText) <$> parseJSON o
instance (ParseYamlFile a, Ord a) => ParseYamlFile (Set.Set a) where
    parseYamlFile base o = parseJSON o >>= ((Set.fromList <$>) . mapM (parseYamlFile base))
instance ParseYamlFile a => ParseYamlFile (V.Vector a) where
    parseYamlFile base o = parseJSON o >>= ((V.fromList <$>) . mapM (parseYamlFile base))

data NonEmptyVector a = NonEmptyVector !a !(V.Vector a)
instance ParseYamlFile a => ParseYamlFile (NonEmptyVector a) where
    parseYamlFile base o = do
        v <- parseYamlFile base o
        if V.null v
            then fail "NonEmptyVector: Expected at least one value"
            else return $ NonEmptyVector (V.head v) (V.tail v)
