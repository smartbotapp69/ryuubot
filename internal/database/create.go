package database

import (
	"context"
	"errors"
	"strings"

	"github.com/jackc/pgx/v5"
)

func EnsureDatabase(ctx context.Context, connectionURL, name string) error {
	if name == "" || strings.IndexFunc(name, func(r rune) bool { return !(r == '_' || r >= 'a' && r <= 'z' || r >= '0' && r <= '9') }) >= 0 {
		return errors.New("nama database tidak valid")
	}
	cfg, err := pgx.ParseConfig(connectionURL); if err != nil { return err }
	cfg.Database = "postgres"
	conn, err := pgx.ConnectConfig(ctx, cfg); if err != nil { return err }; defer conn.Close(ctx)
	var exists bool
	if err=conn.QueryRow(ctx,`SELECT EXISTS(SELECT 1 FROM pg_database WHERE datname=$1)`,name).Scan(&exists);err!=nil{return err}
	if exists{return nil}
	_,err=conn.Exec(ctx,`CREATE DATABASE `+pgx.Identifier{name}.Sanitize())
	return err
}
