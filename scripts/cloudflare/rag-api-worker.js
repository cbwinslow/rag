/**
 * RAG API Worker - Provides API endpoints for RAG functionality
 * Integrates with the autorag system and govinfo data
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      // Route handling
      if (url.pathname === '/api/search' && request.method === 'POST') {
        return await handleSearch(request, env);
      }

      if (url.pathname === '/api/documents' && request.method === 'GET') {
        return await handleGetDocuments(request, env);
      }

      if (url.pathname === '/api/ingest' && request.method === 'POST') {
        return await handleIngest(request, env);
      }

      if (url.pathname === '/api/health' && request.method === 'GET') {
        return await handleHealth(request, env);
      }

      // Default response
      return new Response(JSON.stringify({
        error: 'Not Found',
        message: 'Endpoint not found',
        available_endpoints: ['/api/search', '/api/documents', '/api/ingest', '/api/health']
      }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });

    } catch (error) {
      console.error('Worker error:', error);
      return new Response(JSON.stringify({
        error: 'Internal Server Error',
        message: error.message
      }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }
  }
};

async function handleSearch(request, env) {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  try {
    const body = await request.json();
    const { query, limit = 10, filters = {} } = body;

    if (!query) {
      return new Response(JSON.stringify({
        error: 'Bad Request',
        message: 'Query parameter is required'
      }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Search documents in KV
    const documents = await searchDocuments(env.RAG_DATA, query, limit, filters);

    return new Response(JSON.stringify({
      success: true,
      query,
      results: documents,
      total: documents.length
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Search error:', error);
    return new Response(JSON.stringify({
      error: 'Search Failed',
      message: error.message
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

async function handleGetDocuments(request, env) {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  try {
    const url = new URL(request.url);
    const limit = parseInt(url.searchParams.get('limit') || '10');
    const offset = parseInt(url.searchParams.get('offset') || '0');

    // Get all documents from KV
    const documents = await getAllDocuments(env.RAG_DATA, limit, offset);

    return new Response(JSON.stringify({
      success: true,
      documents,
      limit,
      offset,
      total: documents.length
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Get documents error:', error);
    return new Response(JSON.stringify({
      error: 'Failed to retrieve documents',
      message: error.message
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

async function handleIngest(request, env) {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  try {
    const body = await request.json();
    const { documents, source = 'api' } = body;

    if (!documents || !Array.isArray(documents)) {
      return new Response(JSON.stringify({
        error: 'Bad Request',
        message: 'Documents array is required'
      }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Store documents in KV
    const stored = await storeDocuments(env.RAG_DATA, documents, source);

    return new Response(JSON.stringify({
      success: true,
      message: `${stored.length} documents ingested successfully`,
      stored_count: stored.length
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Ingest error:', error);
    return new Response(JSON.stringify({
      error: 'Ingest Failed',
      message: error.message
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

async function handleHealth(request, env) {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  try {
    // Check KV connectivity
    const testKey = `health-check-${Date.now()}`;
    await env.RAG_DATA.put(testKey, 'test', { expirationTtl: 60 });
    await env.RAG_DATA.delete(testKey);

    return new Response(JSON.stringify({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      services: {
        kv: 'connected'
      }
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Health check error:', error);
    return new Response(JSON.stringify({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message
    }), {
      status: 503,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
}

// Helper functions
async function searchDocuments(kv, query, limit, filters) {
  // Simple text search implementation
  // In a real implementation, you might use a search index or vector similarity
  const keys = await kv.list({ prefix: 'doc:' });
  const results = [];

  for (const key of keys.keys) {
    const doc = await kv.get(key.name);
    if (doc) {
      const document = JSON.parse(doc);
      if (matchesQuery(document, query, filters)) {
        results.push(document);
        if (results.length >= limit) break;
      }
    }
  }

  return results;
}

async function getAllDocuments(kv, limit, offset) {
  const keys = await kv.list({ prefix: 'doc:' });
  const documents = [];

  for (let i = offset; i < Math.min(keys.keys.length, offset + limit); i++) {
    const key = keys.keys[i];
    const doc = await kv.get(key.name);
    if (doc) {
      documents.push(JSON.parse(doc));
    }
  }

  return documents;
}

async function storeDocuments(kv, documents, source) {
  const stored = [];

  for (const doc of documents) {
    const id = `doc:${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    const document = {
      id,
      ...doc,
      source,
      ingested_at: new Date().toISOString(),
      metadata: {
        ...doc.metadata,
        source,
        ingested_at: new Date().toISOString()
      }
    };

    await kv.put(id, JSON.stringify(document));
    stored.push(document);
  }

  return stored;
}

function matchesQuery(document, query, filters) {
  const searchText = `${document.title || ''} ${document.content || ''} ${document.summary || ''}`.toLowerCase();
  const searchQuery = query.toLowerCase();

  // Simple text matching
  if (!searchText.includes(searchQuery)) {
    return false;
  }

  // Apply filters
  if (filters.source && document.source !== filters.source) {
    return false;
  }

  if (filters.date_from && document.ingested_at < filters.date_from) {
    return false;
  }

  if (filters.date_to && document.ingested_at > filters.date_to) {
    return false;
  }

  return true;
}
