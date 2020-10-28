{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Neuron.Zettelkasten.Query.Eval
  ( runQueryURILink,
    queryConnections,
  )
where

import Control.Monad.Except
import Control.Monad.Writer
import Data.Dependent.Sum
import Data.Some
import Neuron.Zettelkasten.Connection
import Neuron.Zettelkasten.Query (runZettelQuery)
import Neuron.Zettelkasten.Query.Error
import Neuron.Zettelkasten.Query.Parser (queryFromURI)
import Neuron.Zettelkasten.Zettel
import Relude
import Text.URI (URI)

-- | Evaluate the given query link and return its results.
--
-- Return Nothing if the link is not a query.
--
-- We need the full list of zettels, for running the query against.
runQueryURILink ::
  ( MonadError QueryResultError m,
    MonadReader [Zettel] m
  ) =>
  URI ->
  m (Maybe (DSum ZettelQuery Identity))
runQueryURILink ul = do
  let mq = queryFromURI OrdinaryConnection ul
  flip traverse mq $ \q ->
    either throwError pure =<< runExceptT (runSomeZettelQuery q)

-- Query connections in the given zettel
--
-- Tell all errors; query parse errors (as already stored in `Zettel`) as well
-- query result errors.
queryConnections ::
  ( -- Errors are written aside, accumulating valid connections.
    MonadWriter [QueryResultError] m,
    -- Running queries requires the zettels list.
    MonadReader [Zettel] m
  ) =>
  Zettel ->
  m [(Connection, Zettel)]
queryConnections Zettel {..} = do
  fmap concat $
    forM zettelQueries $ \someQ ->
      runExceptT (runSomeZettelQuery someQ) >>= \case
        Left e -> do
          tell [e]
          pure mempty
        Right res ->
          pure $ getConnections res
  where
    getConnections :: DSum ZettelQuery Identity -> [(Connection, Zettel)]
    getConnections = \case
      ZettelQuery_ZettelByID _ conn :=> Identity res ->
        [(conn, res)]
      ZettelQuery_ZettelsByTag _ conn _mview :=> Identity res ->
        (conn,) <$> res
      ZettelQuery_Tags _ :=> _ ->
        mempty
      ZettelQuery_TagZettel _ :=> _ ->
        mempty

runSomeZettelQuery ::
  ( MonadError QueryResultError m,
    MonadReader [Zettel] m
  ) =>
  Some ZettelQuery ->
  m (DSum ZettelQuery Identity)
runSomeZettelQuery someQ =
  withSome someQ $ \q -> do
    zs <- ask
    case runZettelQuery zs q of
      Left e ->
        throwError e
      Right res ->
        pure $ q :=> Identity res
