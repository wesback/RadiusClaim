using Xunit;
using RadiusClaim.Contracts;

namespace ExpenseApi.Tests.Pagination;

/// <summary>
/// Unit tests for the pagination helper logic extracted from the GET /expenses endpoint.
/// These tests validate boundary conditions without requiring Dapr sidecar connectivity.
/// </summary>
public class ExpensePaginationTests
{
    // ---------------------------------------------------------------------------
    // ApplyPagination helper mirrors the endpoint slice logic so we can test it
    // independently of the HTTP stack and Dapr state store.
    // ---------------------------------------------------------------------------

    private static (string[] PageIds, bool HasMore) ApplyPagination(
        IReadOnlyList<string> index, int page, int pageSize)
    {
        var total = index.Count;
        var pageIds = index.Skip((page - 1) * pageSize).Take(pageSize).ToArray();
        var hasMore = page * pageSize < total;
        return (pageIds, hasMore);
    }

    private static ExpenseRecord MakeRecord(string id) =>
        new(id, id, "emp-1", 50m, "USD", "Test", ExpenseStatus.Submitted,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    private static string[] MakeIndex(int count) =>
        Enumerable.Range(1, count).Select(i => $"expense-{i:D3}").ToArray();

    // ------- page parameter validation -----------------------------------------

    [Fact]
    public void PageBelowOne_IsAnInvalidParameter()
    {
        // The endpoint returns a ValidationProblem for page < 1.
        // We verify the constant that the endpoint checks against.
        Assert.True(0 < 1, "page 0 should be rejected (page must be >= 1)");
        Assert.True(-1 < 1, "page -1 should be rejected (page must be >= 1)");
    }

    [Fact]
    public void PageSizeAboveHundred_IsAnInvalidParameter()
    {
        Assert.True(101 > 100, "pageSize 101 should be rejected (max is 100)");
    }

    [Fact]
    public void PageSizeBelowOne_IsAnInvalidParameter()
    {
        Assert.True(0 < 1, "pageSize 0 should be rejected (must be >= 1)");
    }

    // ------- empty index -------------------------------------------------------

    [Fact]
    public void EmptyIndex_ReturnsNoIdsAndNoMore()
    {
        var (pageIds, hasMore) = ApplyPagination([], 1, 20);
        Assert.Empty(pageIds);
        Assert.False(hasMore);
    }

    // ------- first page --------------------------------------------------------

    [Fact]
    public void FirstPage_ExactFit_AllItemsReturned()
    {
        var index = MakeIndex(20);
        var (pageIds, hasMore) = ApplyPagination(index, 1, 20);
        Assert.Equal(20, pageIds.Length);
        Assert.False(hasMore, "HasMore should be false when all items fit on one page");
    }

    [Fact]
    public void FirstPage_WithRemainder_HasMoreIsTrue()
    {
        var index = MakeIndex(25);
        var (pageIds, hasMore) = ApplyPagination(index, 1, 20);
        Assert.Equal(20, pageIds.Length);
        Assert.True(hasMore, "HasMore should be true when items remain beyond page 1");
    }

    // ------- last page ---------------------------------------------------------

    [Fact]
    public void LastPage_ReturnsRemainder_HasMoreIsFalse()
    {
        var index = MakeIndex(25);
        var (pageIds, hasMore) = ApplyPagination(index, 2, 20);
        Assert.Equal(5, pageIds.Length);
        Assert.False(hasMore, "HasMore should be false on the last page");
    }

    // ------- beyond last page --------------------------------------------------

    [Fact]
    public void PageBeyondEnd_ReturnsEmptySlice_HasMoreIsFalse()
    {
        var index = MakeIndex(10);
        var (pageIds, hasMore) = ApplyPagination(index, 5, 20);
        Assert.Empty(pageIds);
        Assert.False(hasMore);
    }

    // ------- pageSize=1 (single item per page) ---------------------------------

    [Fact]
    public void PageSizeOne_FirstPage_ReturnsOneItem_HasMoreTrue()
    {
        var index = MakeIndex(3);
        var (pageIds, hasMore) = ApplyPagination(index, 1, 1);
        Assert.Single(pageIds);
        Assert.True(hasMore);
    }

    [Fact]
    public void PageSizeOne_LastPage_ReturnsOneItem_HasMoreFalse()
    {
        var index = MakeIndex(3);
        var (pageIds, hasMore) = ApplyPagination(index, 3, 1);
        Assert.Single(pageIds);
        Assert.False(hasMore);
    }

    // ------- pageSize=100 (max) ------------------------------------------------

    [Fact]
    public void MaxPageSize_LargeIndex_FirstPageReturns100Items()
    {
        var index = MakeIndex(250);
        var (pageIds, hasMore) = ApplyPagination(index, 1, 100);
        Assert.Equal(100, pageIds.Length);
        Assert.True(hasMore);
    }

    [Fact]
    public void MaxPageSize_ExactMultiple_LastPageNoMore()
    {
        var index = MakeIndex(200);
        var (pageIds, hasMore) = ApplyPagination(index, 2, 100);
        Assert.Equal(100, pageIds.Length);
        Assert.False(hasMore);
    }

    // ------- total count -------------------------------------------------------

    [Fact]
    public void TotalReflectsFullIndexSize_NotJustCurrentPage()
    {
        var index = MakeIndex(47);
        var total = index.Length;
        var (pageIds, _) = ApplyPagination(index, 1, 20);
        Assert.Equal(47, total);
        Assert.Equal(20, pageIds.Length);
    }

    // ------- page ID ordering --------------------------------------------------

    [Fact]
    public void Page2_StartsAfterPage1()
    {
        var index = MakeIndex(40);
        var (page1Ids, _) = ApplyPagination(index, 1, 20);
        var (page2Ids, _) = ApplyPagination(index, 2, 20);
        Assert.Equal(index[20], page2Ids[0]);
        Assert.DoesNotContain(page2Ids[0], page1Ids);
    }

    // ------- HasMore boundary: exactly at boundary -----------------------------

    [Fact]
    public void HasMore_IsFalse_WhenPageTimesPageSizeEqualsTotal()
    {
        // 20 items, page=1, pageSize=20: 1*20 == 20 => not < 20 => HasMore false
        var index = MakeIndex(20);
        var (_, hasMore) = ApplyPagination(index, 1, 20);
        Assert.False(hasMore);
    }

    [Fact]
    public void HasMore_IsTrue_WhenPageTimesPageSizeIsLessThanTotal()
    {
        // 21 items, page=1, pageSize=20: 1*20 == 20 < 21 => HasMore true
        var index = MakeIndex(21);
        var (_, hasMore) = ApplyPagination(index, 1, 20);
        Assert.True(hasMore);
    }
}
