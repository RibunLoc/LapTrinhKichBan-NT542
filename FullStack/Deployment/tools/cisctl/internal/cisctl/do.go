package cisctl

import (
	"context"
	"errors"

	"github.com/digitalocean/godo"
	"golang.org/x/oauth2"
)

type DOClient struct {
	c *godo.Client
}

func NewDOClient(token string) (*DOClient, error) {
	if token == "" {
		return nil, errors.New("empty DO token")
	}
	tokenSource := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token})
	oauthClient := oauth2.NewClient(context.Background(), tokenSource)
	return &DOClient{c: godo.NewClient(oauthClient)}, nil
}

func (c *DOClient) ListDropletsByTag(ctx context.Context, tag string) ([]godo.Droplet, error) {
	var all []godo.Droplet
	opt := &godo.ListOptions{PerPage: 200, Page: 1}
	for {
		droplets, resp, err := c.c.Droplets.ListByTag(ctx, tag, opt)
		if err != nil {
			return nil, err
		}
		all = append(all, droplets...)
		if resp == nil || resp.Links == nil || resp.Links.IsLastPage() {
			break
		}
		page, err := resp.Links.CurrentPage()
		if err != nil {
			break
		}
		opt.Page = page + 1
	}
	return all, nil
}

func (c *DOClient) ListFirewalls(ctx context.Context) ([]godo.Firewall, error) {
	var all []godo.Firewall
	opt := &godo.ListOptions{PerPage: 200, Page: 1}
	for {
		fws, resp, err := c.c.Firewalls.List(ctx, opt)
		if err != nil {
			return nil, err
		}
		all = append(all, fws...)
		if resp == nil || resp.Links == nil || resp.Links.IsLastPage() {
			break
		}
		page, err := resp.Links.CurrentPage()
		if err != nil {
			break
		}
		opt.Page = page + 1
	}
	return all, nil
}

func HasFeature(d godo.Droplet, feature string) bool {
	for _, f := range d.Features {
		if f == feature {
			return true
		}
	}
	return false
}

func DropletPublicIPv4(d godo.Droplet) string {
	for _, n := range d.Networks.V4 {
		if n.Type == "public" && n.IPAddress != "" {
			return n.IPAddress
		}
	}
	return ""
}

func HasString(values []string, v string) bool {
	for _, s := range values {
		if s == v {
			return true
		}
	}
	return false
}

