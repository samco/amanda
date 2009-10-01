/*
 * Amanda, The Advanced Maryland Automatic Network Disk Archiver
 * Copyright (c) 1999 University of Maryland
 * All Rights Reserved.
 *
 * Permission to use, copy, modify, distribute, and sell this software and its
 * documentation for any purpose is hereby granted without fee, provided that
 * the above copyright notice appear in all copies and that both that
 * copyright notice and this permission notice appear in supporting
 * documentation, and that the name of U.M. not be used in advertising or
 * publicity pertaining to distribution of the software without specific,
 * written prior permission.  U.M. makes no representations about the
 * suitability of this software for any purpose.  It is provided "as is"
 * without express or implied warranty.
 *
 * U.M. DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE, INCLUDING ALL
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS, IN NO EVENT SHALL U.M.
 * BE LIABLE FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
 * OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
 * CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 * Authors: the Amanda Development Team.  Its members are listed in a
 * file named AUTHORS, in the root directory of this distribution.
 */

/*
 * $Id: ssh-security.c,v 1.23 2006/08/21 20:17:10 martinea Exp $
 *
 * ssh-security.c - security and transport over ssh or a ssh-like command.
 *
 * XXX still need to check for initial keyword on connect so we can skip
 * over shell garbage and other stuff that ssh might want to spew out.
 */

#include "amanda.h"
#include "util.h"
#include "event.h"
#include "packet.h"
#include "security.h"
#include "security-util.h"
#include "stream.h"

/*
 * Number of seconds ssh has to start up
 */
#define	CONNECT_TIMEOUT	20

/*
 * Magic values for ssh_conn->handle
 */
#define	H_TAKEN	-1		/* ssh_conn->tok was already read */
#define	H_EOF	-2		/* this connection has been shut down */

/*
 * Interface functions
 */
static void	ssh_connect(const char *, char *(*)(char *, void *),
			void (*)(void *, security_handle_t *, security_status_t),
			void *, void *);

/*
 * This is our interface to the outside world.
 */
const security_driver_t ssh_security_driver = {
    "SSH",
    ssh_connect,
    sec_accept,
    sec_close,
    stream_sendpkt,
    stream_recvpkt,
    stream_recvpkt_cancel,
    tcpma_stream_server,
    tcpma_stream_accept,
    tcpma_stream_client,
    tcpma_stream_close,
    sec_stream_auth,
    sec_stream_id,
    tcpm_stream_write,
    tcpm_stream_read,
    tcpm_stream_read_sync,
    tcpm_stream_read_cancel,
    tcpm_close_connection,
    NULL,
    NULL
};

static int newhandle = 1;

/*
 * Local functions
 */
static int runssh(struct tcp_conn *, const char *, const char *, const char *);

/*
 * ssh version of a security handle allocator.  Logically sets
 * up a network "connection".
 */
static void
ssh_connect(
    const char *	hostname,
    char *		(*conf_fn)(char *, void *),
    void		(*fn)(void *, security_handle_t *, security_status_t),
    void *		arg,
    void *		datap)
{
    int result;
    struct sec_handle *rh;
    char *amandad_path=NULL, *client_username=NULL, *ssh_keys=NULL;

    assert(fn != NULL);
    assert(hostname != NULL);

    auth_debug(1, "ssh_connect: %s\n", hostname);

    rh = alloc(SIZEOF(*rh));
    security_handleinit(&rh->sech, &ssh_security_driver);
    rh->hostname = NULL;
    rh->rs = NULL;
    rh->ev_timeout = NULL;
    rh->rc = NULL;

    /* get the canonical hostname */
    rh->hostname = NULL;
    if ((result = resolve_hostname(hostname, 0, NULL, &rh->hostname)) != 0
	 || rh->hostname == NULL) {
	security_seterror(&rh->sech,
	    _("ssh_security could not find canonical name for '%s': %s"),
	    hostname, gai_strerror(result));
	(*fn)(arg, &rh->sech, S_ERROR);
	return;
    }
    rh->rs = tcpma_stream_client(rh, newhandle++);
    rh->rc->conf_fn = conf_fn;
    rh->rc->datap = datap;

    if (rh->rs == NULL)
	goto error;

    amfree(rh->hostname);
    rh->hostname = stralloc(rh->rs->rc->hostname);

    /*
     * We need to open a new connection.
     *
     * XXX need to eventually limit number of outgoing connections here.
     */
    if(conf_fn) {
	amandad_path    = conf_fn("amandad_path", datap);
	client_username = conf_fn("client_username", datap);
	ssh_keys        = conf_fn("ssh_keys", datap);
    }
    if(rh->rc->read == -1) {
	if (runssh(rh->rs->rc, amandad_path, client_username, ssh_keys) < 0) {
	    security_seterror(&rh->sech, _("can't connect to %s: %s"),
			      hostname, rh->rs->rc->errmsg);
	    goto error;
	}
	rh->rc->refcnt++;
    }

    /*
     * The socket will be opened async so hosts that are down won't
     * block everything.  We need to register a write event
     * so we will know when the socket comes alive.
     *
     * Overload rh->rs->ev_read to provide a write event handle.
     * We also register a timeout.
     */
    rh->fn.connect = fn;
    rh->arg = arg;
    rh->rs->ev_read = event_register((event_id_t)rh->rs->rc->write, EV_WRITEFD,
	sec_connect_callback, rh);
    rh->ev_timeout = event_register((event_id_t)CONNECT_TIMEOUT, EV_TIME,
	sec_connect_timeout, rh);

    return;

error:
    (*fn)(arg, &rh->sech, S_ERROR);
}

/*
 * Forks a ssh to the host listed in rc->hostname
 * Returns negative on error, with an errmsg in rc->errmsg.
 */
static int
runssh(
    struct tcp_conn *	rc,
    const char *	amandad_path,
    const char *	client_username,
    const char *	ssh_keys)
{
    int rpipe[2], wpipe[2];
    char *xamandad_path = (char *)amandad_path;
    char *xclient_username = (char *)client_username;
    char *xssh_keys = (char *)ssh_keys;

    memset(rpipe, -1, SIZEOF(rpipe));
    memset(wpipe, -1, SIZEOF(wpipe));
    if (pipe(rpipe) < 0 || pipe(wpipe) < 0) {
	rc->errmsg = newvstrallocf(rc->errmsg, _("pipe: %s"), strerror(errno));
	return (-1);
    }

    switch (rc->pid = fork()) {
    case -1:
	rc->errmsg = newvstrallocf(rc->errmsg, _("fork: %s"), strerror(errno));
	aclose(rpipe[0]);
	aclose(rpipe[1]);
	aclose(wpipe[0]);
	aclose(wpipe[1]);
	return (-1);
    case 0:
	dup2(wpipe[0], 0);
	dup2(rpipe[1], 1);
	break;
    default:
	rc->read = rpipe[0];
	aclose(rpipe[1]);
	rc->write = wpipe[1];
	aclose(wpipe[0]);
	return (0);
    }

    /* drop root privs for good */
    set_root_privs(-1);

    safe_fd(-1, 0);

    if(!xamandad_path || strlen(xamandad_path) <= 1) 
	xamandad_path = vstralloc(amlibexecdir, "/", "amandad", NULL);
    if(!xclient_username || strlen(xclient_username) <= 1)
	xclient_username = CLIENT_LOGIN;
    if(!ssh_keys || strlen(ssh_keys) <= 1) {
	execlp(SSH, SSH, SSH_OPTIONS, "-l", xclient_username,
	       rc->hostname, xamandad_path, "-auth=ssh", "amdump", "amindexd",
	       "amidxtaped", (char *)NULL);
    }
    else {
	execlp(SSH, SSH, SSH_OPTIONS, "-l", xclient_username,
	       "-i", xssh_keys, rc->hostname, xamandad_path, "-auth=ssh",
	       "amdump", "amindexd", "amidxtaped", (char *)NULL);
    }
    error("error: couldn't exec %s: %s", SSH, strerror(errno));

    /* should never go here, shut up compiler warning */
    return(-1);
}
