/* $Id: vertex_factory.c 48 2005-04-13 15:56:25Z ron $
   Written by Adam Siepel, Spring 2001 
   Copyright 2001, Adam Siepel */

/* "Factory" for vertices, allowing more efficient memory allocation
   and deallocation.  Compile with -DTHREADSAFE for concurrent access
   from multiple threads. */

#include <stdlib.h>
#include "vertex_factory.h"
#include <stdio.h>

#define VFWIDTH 512 //1024 
//VFWIDTH should be variable by gene size

void
clean_vf ( VertexFactory * vf, int ngenes, void ( *clear_mem ) ( void * ),
           void *arg )
{
    int i, j;
    int length1;
    vf->offseth = 0;
    vf->nalloc = 0;
    vf->ngenes = ngenes;
    vf->clear_mem = clear_mem;
    vf->clear_mem_arg = arg;
    length1 = vf->length - 1;
    for ( i = 0; i < vf->width; i++ )
    {
        for ( j = 0; j < length1; j++ )
        {
            vf->vertices[i][j].perm = &( vf->perms[i][j * ngenes] );
            vf->vertices[i][j].next = &( vf->vertices[i][j + 1] );
        }
        if ( i < vf->width - 1 )
        {
            vf->vertices[i][j].perm = &( vf->perms[i][j * ngenes] );
            vf->vertices[i][j].next = &( vf->vertices[i + 1][0] );
        }
        else
        {
            vf->vertices[i][j].perm = &( vf->perms[i][j * ngenes] );
            vf->vertices[i][j].next = NULL;
        }
    }
    vf->head = &( vf->vertices[0][0] );
    vf->tail = &( vf->vertices[vf->width - 1][length1] );
#ifdef THREADSAFE
    pthread_mutex_init ( &vf->mutex, NULL );
#endif

    return;

}


int
vf_no_free_vertex ( VertexFactory * vf ,int ps_size)
{
 /*   int totalsize;
    if( 1 == vf->full)
        totalsize = VFWIDTH*(vf->length);
    else
         totalsize = vf->capacity;
    if ((totalsize-1)>ps_size)
    {
    fprintf(stdout,"free vertex: %d-1 > %d\n",totalsize,ps_size);
        return 0;    
    }
    else
    {
        return 1;
    }
    */
    if ( vf->freevertex > 0) return 0;
    else return 1;
}


void
vf_clear ( VertexFactory * vf)
{
    int i,j;
    int wide, len;
    wide = vf-> length;
    if(1==vf->full)
    {
        vf->freevertex = VFWIDTH*(vf->length);
        len = VFWIDTH;
    }
    else
    {
        vf->freevertex = vf->capacity;
        len = vf->width;
    }
    for ( i = 0; i < len; i++ )
    {
        for ( j = 0; j < wide; j++ )
            vf->vertices[i][j].inuse = 0;
    }
}

/* Last two arguments pertain to a function to be called when capacity
   has been reached, before reallocating more memory.  Pass NULL for
   both if you do not wish to specify such a function */
VertexFactory *
new_vf ( int startsize, int ngenes, void ( *clear_mem ) ( void * ),
         void *arg )
{
    //startsize is set to VFWIDTH by default = 512
    //when ngenes is too big, following malloc will alloc super big memory block
    //reduce the startsize then
    int fitsize = startsize;
    if(ngenes>64)
    {
        fitsize = (int)( fitsize/ ((int)(ngenes/64)+1) );
    //    fprintf(stdout,"ngenes is %d,reduce the startsize to %d\n",ngenes,fitsize);
    }
    startsize = fitsize;
    int i;
    VertexFactory *vf;
    vf = ( VertexFactory * ) malloc ( sizeof ( VertexFactory ) );
    vf->vertices = ( Vertex ** ) malloc ( VFWIDTH * sizeof ( Vertex * ) );
    vf->vertices[0] = ( Vertex * ) malloc ( startsize * sizeof ( Vertex ) );
    vf->width = 1;
    vf->perms = ( int ** ) malloc ( VFWIDTH * sizeof ( int * ) );
    vf->perms[0] = ( int * ) malloc ( startsize * ngenes * sizeof ( int ) );
    vf->nalloc = 0;
    vf->ngenes = ngenes;
    vf->uncondensedNumGenes = ngenes;
    vf->capacity = startsize;
    vf->length = startsize;
    vf->clear_mem = clear_mem;
    vf->clear_mem_arg = arg;

    for ( i = 0; i < startsize - 1; i++ )
    {
        vf->vertices[0][i].perm = &( vf->perms[0][i * ngenes] );
        vf->vertices[0][i].next = &( vf->vertices[0][i + 1] );
    }
    vf->vertices[0][i].perm = &( vf->perms[0][i * ngenes] );
    //vf->vertices[0][i].next = vf->tail; 
    vf->vertices[0][i].next = NULL; 
    /* to avoid the if block in the for block */
    vf->tail = &( vf->vertices[0][i] );
    vf->head = &( vf->vertices[0][0] );

    vf->offseth = 0; 
    vf->full = 0; // sign if we already init all memory in the block.
    vf->freevertex = startsize;

#ifdef THREADSAFE
    pthread_mutex_init ( &vf->mutex, NULL );
#endif

    return vf;
}

Vertex *
get_vertex ( VertexFactory * vf )
{
    int oldcap, i;
    Vertex *retval;
    int width1;
    int length;
#ifdef THREADSAFE
    pthread_mutex_lock ( &vf->mutex );
#endif
//what if we reach the end of vf->vertices, reuse the first one of it?
//check vf->width <>  VFWIDTH

    if ( vf->width >= VFWIDTH )     
    {
// fprintf(stdout,"reach the end of VFWIDTH, reuse memory\n"); fflush(stdout);
        vf->full = 1;
        vf->width = 1;
        vf->nalloc=0;
        vf->offseth = 0;
        vf->tail = &( vf->vertices[0][vf->length-1] );
        vf->head = &( vf->vertices[0][0] );
    }
    
    if (( vf->head == NULL ))
    {
        length = vf->length;
        width1 = vf->width - 1;
       // fprintf(stdout,"end of width1=%d\n",width1); fflush(stdout);
        if ( vf->clear_mem != NULL )
        {
#ifdef THREADSAFE
            pthread_mutex_unlock ( &vf->mutex );
#endif
            fprintf ( stderr, "Invoking clear_mem\n" );
            vf->clear_mem ( vf->clear_mem_arg );
#ifdef THREADSAFE
            pthread_mutex_lock ( &vf->mutex );
#endif
        }
        oldcap = vf->capacity;
        vf->width++;
        width1 = vf->width - 1;
    //    fprintf(stdout,"vf->width++=%d\n",vf->width); fflush(stdout);
        if( 0 == vf->full) //this is the first time we go through this memory block
        {
        vf->vertices[width1] =
            ( Vertex * ) malloc ( length * sizeof ( Vertex ) );
        vf->perms[width1] =
            ( int * ) malloc ( length * vf->uncondensedNumGenes *
                               sizeof ( int ) );
        vf->capacity += length;
        vf->freevertex += length;
        }
        else { 
        //we already went through the memory block,
        //no need to alloc again
        }
        for ( i = 0; i < length - 1; i++ )
        {
            vf->vertices[width1][i].perm =
                &( vf->perms[width1][i * vf->ngenes] );
            vf->vertices[width1][i].next = &( vf->vertices[width1][i + 1] );
        }
        vf->vertices[width1][i].perm = &( vf->perms[width1][i * vf->ngenes] );
        vf->vertices[width1][i].next = NULL;
        vf->tail = &( vf->vertices[width1][i] );
        vf->head = &( vf->vertices[width1][0] );
        vf->offseth = 0;
    }
    //fprintf(stdout,"get vertex at offsetH=%d\n",vf->offseth); fflush(stdout);
    
    vf->nalloc ++;
    vf->offseth ++;

    retval = vf->head;
//    retval->NO = vf->nalloc;
    if( 1==(retval->inuse))
    {
 //       fprintf(stdout,"current vertex is in use, get the next one,freevertex=%d \n", vf->freevertex);
        vf->head = retval->next;
        retval = get_vertex(vf);
    }
    else
    {
 //       retval->inuse = 1;
        vf->head = retval->next;
    //    vf->freevertex --;
    }

  //      vf->head = retval->next;

#ifdef THREADSAFE
    pthread_mutex_unlock ( &vf->mutex );
#endif

    return retval;
}


void
mark_vertex (  VertexFactory * vf, Vertex * v )
{
    vf->freevertex --;
    v->inuse = 1;
}


void
return_vertex ( VertexFactory * vf, Vertex * v )
{
    v->inuse = 0;
  //  vf->freevertex ++;
    /*
#ifdef THREADSAFE
    pthread_mutex_lock ( &vf->mutex );
#endif

    vf->nalloc--;
    vf->offsett ++;

    fprintf(stdout,"add vertex to offsetT=%d,offsetH is %d\n",
            vf->offsett,vf->offseth);
    fflush(stdout);
   
   ( vf->tail )->next = v;
    vf->tail = v;
    v->next = NULL;

#ifdef THREADSAFE
    pthread_mutex_unlock ( &vf->mutex );
#endif
*/
}

void
vf_free ( VertexFactory * vf )
{
    int i;
    int width;
    if (1==vf->full) width = VFWIDTH;
    else width = vf->width;
    for ( i = 0; i < width; i++ )
        free ( vf->vertices[i] );
    for ( i = 0; i < width; i++ )
        free ( vf->perms[i] );

    free ( vf->vertices );
    free ( vf->perms );
    free ( vf );
}
